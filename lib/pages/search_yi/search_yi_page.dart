import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/web_yi/web_yi_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/request/query_manager.dart';
import 'package:kazumi/utils/logger.dart';
import 'package:logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../bean/appbar/sys_app_bar.dart';
import '../../bean/widget/error_widget.dart';
import '../video/video_controller.dart';

class SearchYiPage extends StatefulWidget {
  const SearchYiPage({
    super.key,
  });

  @override
  State<SearchYiPage> createState() => _SearchYiPageState();
}

class _SearchYiPageState extends State<SearchYiPage>
    with SingleTickerProviderStateMixin {
  QueryManager? queryManager;
  final InfoController infoController = InfoController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final VideoPageController videoPageController =
      Modular.get<VideoPageController>();
  final PluginsController pluginsController = Modular.get<PluginsController>();
  late TabController tabController;
  late WebYiController webYiController;

  //分页信息
  final Map<String, int> _currentPages = {}; // 当前页码
  final Map<String, int> _totalPages = {}; // 总页数

  @override
  void initState() {
    super.initState();

    for (var plugin in pluginsController.pluginList) {
      _currentPages[plugin.name] = 1;
      _totalPages[plugin.name] = 0;
    }

    queryManager = QueryManager(infoController: infoController);
    queryManager?.queryAllSource('');
    tabController =
        TabController(length: pluginsController.pluginList.length, vsync: this);

    webYiController = Modular.get<WebYiController>();
  }

  int _generateUniqueId(String name) {
    // 将字符串编码为UTF-8字节
    final bytes = utf8.encode(name);

    // 生成SHA-256哈希
    final digest = sha256.convert(bytes);

    // 取前8字节（64位）转换为无符号整数
    final hashInt = BigInt.parse(
      '0x${digest.bytes.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}',
    );

    // 取模约束到小于20亿的范围
    return (hashInt % BigInt.from(2000000000)).toInt() + 100000000;
  }

  @override
  void dispose() {
    queryManager?.cancel();
    _searchController.dispose();
    videoPageController.currentEpisode = 1;
    _focusNode.dispose();
    tabController.dispose();
    webYiController.dispose();
    super.dispose();
  }

  void _search(String keyword) {
    queryManager?.queryAllSource(keyword);
    for (var plugin in pluginsController.pluginList) {
      _currentPages[plugin.name] = 1;
      _totalPages[plugin.name] = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
        appBar: SysAppBar(
          title: Visibility(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              cursorColor: Theme.of(context).colorScheme.primary,
              decoration: InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.never,
                labelText: '输入搜索内容',
                alignLabelWithHint: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    _search(_searchController.text);
                  },
                ),
              ),
              style:
                  TextStyle(color: isLight ? Colors.black87 : Colors.white70),
              onSubmitted: (value) => _search(value),
            ),
          ),
          actions: [
            if (MediaQuery.of(context).orientation == Orientation.portrait)
              IconButton(
                tooltip: '历史记录',
                onPressed: () => Modular.to.pushNamed('/settings/history/'),
                icon: const Icon(Icons.history),
              ),
          ],
        ),
        body: Scaffold(
          appBar: AppBar(
            toolbarHeight: 0, // 隐藏顶部区域
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(27), // 固定 TabBar 高度
              child: TabBar(
                isScrollable: true,
                controller: tabController,
                tabs: pluginsController.pluginList
                    .map((plugin) => Observer(
                          builder: (context) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                plugin.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: Theme.of(context)
                                      .textTheme
                                      .titleMedium!
                                      .fontSize,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 5.0),
                              Container(
                                width: 8.0,
                                height: 8.0,
                                decoration: BoxDecoration(
                                  color: infoController.pluginSearchStatus[
                                              plugin.name] ==
                                          'success'
                                      ? Colors.green
                                      : (infoController.pluginSearchStatus[
                                                  plugin.name] ==
                                              'pending'
                                          ? Colors.grey
                                          : Colors.red),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          body: Observer(
            builder: (context) => TabBarView(
              controller: tabController,
              children: List.generate(pluginsController.pluginList.length,
                  (pluginIndex) {
                var plugin = pluginsController.pluginList[pluginIndex];
                var cardList = <Widget>[];
                for (var searchResponse
                    in infoController.pluginSearchResponseList) {
                  if (searchResponse.pluginName == plugin.name) {
                    for (var searchItem in searchResponse.data) {
                      cardList.add(Card(
                        color: Colors.transparent,
                        child: SizedBox(
                          height: 100, // 固定卡片高度
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.center, // 垂直居中
                            children: [
                              // 左侧固定高度图片
                              _buildImageWidget(
                                  searchItem.img, plugin, searchItem.src),
                              // 右侧文字区域
                              Expanded(
                                child: Container(
                                  height: 100,
                                  alignment: Alignment.centerLeft,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      searchItem.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: plugin.chapterRoads.isEmpty
                                            ? Colors.white
                                            : null,
                                      ),
                                    ),
                                    // 关键修改部分：添加点击条件判断
                                    onTap: plugin.chapterRoads.isEmpty
                                        ? null
                                        : () async {
                                            // 根据变量实际情况可能需要用空字符串判断
                                            KazumiDialog.showLoading(
                                                msg: '获取中');
                                            String todayDate = DateTime.now()
                                                .toString()
                                                .split(' ')[0];
                                            videoPageController.bangumiItem =
                                                BangumiItem(
                                              id: _generateUniqueId(
                                                  searchItem.name),
                                              type: _generateUniqueId(
                                                  searchItem.name),
                                              name: searchItem.name,
                                              nameCn: searchItem.name,
                                              summary:
                                                  "影片《${searchItem.name}》是通过规则${plugin.name}直接搜索得到。\r无法获取bangumi的数据，但支持除此以外包括追番，观看记录之外的绝大部分功能。",
                                              airDate: todayDate,
                                              airWeekday: 0,
                                              rank: 0,
                                              images: {
                                                'small': searchItem.img,
                                                'grid': searchItem.img,
                                                'large': searchItem.img,
                                                'medium': searchItem.img,
                                                'common': searchItem.img,
                                              },
                                              tags: [],
                                              alias: [],
                                              ratingScore: 0.0,
                                              votes: 0,
                                              votesCount: [],
                                              info: '',
                                            );

                                            videoPageController.currentPlugin =
                                                plugin;
                                            videoPageController.title =
                                                searchItem.name;
                                            videoPageController.src =
                                                searchItem.src;
                                            try {
                                              await videoPageController
                                                  .queryRoads(searchItem.src,
                                                      plugin.name);
                                              KazumiDialog.dismiss();
                                              Modular.to.pushNamed('/video/');
                                            } catch (e) {
                                              KazumiLogger().log(
                                                  Level.error, e.toString());
                                              KazumiDialog.dismiss();
                                            }
                                          },
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ));
                    }
                  }
                }
                return infoController.pluginSearchStatus[plugin.name] ==
                        'pending'
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          if (infoController.pluginSearchStatus[plugin.name] ==
                              'error')
                            Expanded(
                              child: GeneralErrorWidget(
                                errMsg: '${plugin.name} 检索失败 重试或切换到其他视频来源',
                                actions: [
                                  GeneralErrorButton(
                                    onPressed: () {
                                      queryManager?.querySourceWithPage(
                                          _searchController.text,
                                          plugin.name,
                                          _currentPages[plugin.name] ?? 1,
                                          reload: true);
                                    },
                                    text: '重试',
                                  ),
                                  GeneralErrorButton(
                                    onPressed: () {
                                      KazumiDialog.show(builder: (context) {
                                        return AlertDialog(
                                          title: const Text('退出确认'),
                                          content: const Text(
                                              '您想要离开 Kazumi 并在浏览器中打开此视频链接吗？'),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    KazumiDialog.dismiss(),
                                                child: const Text('取消')),
                                            TextButton(
                                                onPressed: () {
                                                  KazumiDialog.dismiss();
                                                  launchUrl(Uri.parse(
                                                      plugin.baseUrl));
                                                },
                                                child: const Text('确认')),
                                          ],
                                        );
                                      });
                                    },
                                    text: 'web',
                                  ),
                                ],
                              ),
                            )
                          else if (cardList.isEmpty)
                            Expanded(
                              child: GeneralErrorWidget(
                                errMsg:
                                    '${plugin.name} 本页无结果 使用其他搜索词或切换到其他视频来源',
                                actions: [
                                  GeneralErrorButton(
                                    onPressed: () {
                                      KazumiDialog.show(builder: (context) {
                                        return AlertDialog(
                                          title: const Text('退出确认'),
                                          content: const Text(
                                              '您想要离开 Kazumi 并在浏览器中打开此视频链接吗？'),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    KazumiDialog.dismiss(),
                                                child: const Text('取消')),
                                            TextButton(
                                                onPressed: () {
                                                  KazumiDialog.dismiss();
                                                  launchUrl(Uri.parse(
                                                      plugin.baseUrl));
                                                },
                                                child: const Text('确认')),
                                          ],
                                        );
                                      });
                                    },
                                    text: 'web',
                                  ),
                                ],
                              ),
                            )
                          else
                            Expanded(
                              child: ListView(children: cardList),
                            ),
                          buildPagination(plugin), // 所有状态都显示分页控件
                        ],
                      );
              }),
            ),
          ),
        ));
  }

  Widget _buildImageWidget(String imgUrl, Plugin plugin, String resultUrl) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      height: 100,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          // 新增手势检测层
          onTap: () {
            String url = '';
            if (resultUrl.contains(plugin.baseUrl)) {
              url = resultUrl;
            } else {
              url = plugin.baseUrl + resultUrl;
            }
            KazumiDialog.show(builder: (context) {
              return AlertDialog(
                title: const Text('退出确认'),
                content: const Text('您想要离开 Kazumi 并在浏览器中打开此视频链接吗？'),
                actions: [
                  TextButton(
                      onPressed: () => KazumiDialog.dismiss(),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () {
                        KazumiDialog.dismiss();
                        launchUrl(Uri.parse(url));
                      },
                      child: const Text('确认')),
                ],
              );
            });
          },
          child: Image.network(
            imgUrl,
            fit: BoxFit.fitHeight,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[300],
                width: 70,
                child: const Icon(Icons.broken_image),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget buildPagination(Plugin plugin) {
    int currentPage = _currentPages[plugin.name] ?? 1;
    int totalPage = _totalPages[plugin.name] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 35,
              minHeight: 35,
            ),
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: currentPage > 1
                ? () {
                    _currentPages[plugin.name] = currentPage - 1;
                    queryManager?.querySourceWithPage(
                        _searchController.text, plugin.name, currentPage - 1);
                  }
                : null,
            icon: const Icon(Icons.arrow_back),
            color: Theme.of(context).primaryColor,
            disabledColor: Colors.grey[400],
          ),
          SizedBox(
            width: 56, // 缩小输入框宽度
            child: TextField(
              controller: TextEditingController(text: currentPage.toString()),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12, // 缩小字体
              ),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                // 关键设置！压缩输入框高度
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                // 缩小垂直内边距
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6), // 缩小圆角
                  borderSide: BorderSide(
                    color: Colors.grey[400]!,
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: Colors.grey[400]!,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 1.0, // 缩小边框宽度
                  ),
                ),
              ),
              onSubmitted: (value) {
                int page = int.tryParse(value) ?? 1;
                _currentPages[plugin.name] = page;
                queryManager?.querySourceWithPage(
                    _searchController.text, plugin.name, page);
              },
            ),
          ),
          IconButton(
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 35,
              minHeight: 35,
            ),
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: currentPage < totalPage || totalPage == 0
                ? () {
                    _currentPages[plugin.name] = currentPage + 1;
                    queryManager?.querySourceWithPage(
                        _searchController.text, plugin.name, currentPage + 1);
                  }
                : null,
            icon: const Icon(Icons.arrow_forward),
            color: Theme.of(context).primaryColor,
            disabledColor: Colors.grey[400],
          ),
        ],
      ),
    );
  }
}
