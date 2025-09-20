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
                      cardList.add(
                        Card(
                          color: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            // 圆角设计
                          ),
                          child: SizedBox(
                            height: 120, // 稍微增加高度以容纳标签
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: plugin.chapterRoads.isEmpty
                                  ? null
                                  : () async {
                                      // 点击处理逻辑保持不变
                                      KazumiDialog.showLoading(msg: '获取中');
                                      String todayDate = DateTime.now()
                                          .toString()
                                          .split(' ')[0];
                                      videoPageController.bangumiItem =
                                          BangumiItem(
                                        id: _generateUniqueId(searchItem.name),
                                        type:
                                            _generateUniqueId(searchItem.name),
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
                                      videoPageController.src = searchItem.src;
                                      try {
                                        await videoPageController.queryRoads(
                                            searchItem.src, plugin.name);
                                        KazumiDialog.dismiss();
                                        Modular.to.pushNamed('/video/');
                                      } catch (e) {
                                        KazumiLogger()
                                            .log(Level.error, e.toString());
                                        KazumiDialog.dismiss();
                                      }
                                    },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // 左侧图片
                                  _buildImageWidget(
                                      searchItem.img, plugin, searchItem.src),

                                  const SizedBox(width: 12), // 添加间距

                                  // 右侧内容区域
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        // 标题
                                        Text(
                                          searchItem.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: plugin.chapterRoads.isEmpty
                                                ? Colors.white
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
                                          ),
                                          maxLines: 2, // 限制最多两行
                                          overflow: TextOverflow
                                              .ellipsis, // 超出部分显示省略号
                                        ),

                                        const SizedBox(height: 8),
                                        // 添加间距

                                        // 标签区域
                                        if (searchItem.tags.isNotEmpty)
                                          SizedBox(
                                            height: 28, // 固定标签区域高度
                                            child: ListView(
                                              scrollDirection:
                                                  Axis.horizontal, // 水平滚动
                                              children: searchItem.tags.entries
                                                  .map((entry) {
                                                return Container(
                                                  margin: const EdgeInsets.only(
                                                      right: 6),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Text(
                                                    '${entry.key}:${entry.value}',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
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
                                              '您想要离开 Kazumi 并在浏览器中打开此链接吗？'),
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
                                              '您想要离开 Kazumi 并在浏览器中打开此链接吗？'),
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
    // 处理空图片URL的情况
    if (imgUrl.isEmpty) {
      return _buildPlaceholderWidget(plugin, resultUrl);
    }

    return Align(
      alignment: Alignment.centerRight, // 确保图片靠右对齐
      child: Container(
        // 移除左侧所有空白，仅保留右侧必要间距
        margin: const EdgeInsets.only(right: 4),
        height: 120, // 与行高保持一致
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: () => _handleImageTap(plugin, resultUrl),
            child: Image.network(
              imgUrl,
              fit: BoxFit.contain, // 保持原始比例
              alignment: Alignment.center,
              cacheWidth: 200,
              cacheHeight: 300,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _buildLoadingWidget();
              },
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorImage(plugin, resultUrl);
              },
            ),
          ),
        ),
      ),
    );
  }

// 构建占位符组件（无图状态）
  Widget _buildPlaceholderWidget(Plugin plugin, String resultUrl) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      width: 84,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.image_not_supported, color: Colors.grey, size: 24),
          Text('无图片', style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

// 构建加载中组件
  Widget _buildLoadingWidget() {
    return Container(
      width: 84,
      height: 120,
      color: Colors.grey[300],
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor:
              AlwaysStoppedAnimation<Color>(Colors.blue.withOpacity(0.7)),
        ),
      ),
    );
  }

// 构建错误状态图片组件（调整高度适配）
  Widget _buildErrorImage(Plugin plugin, String resultUrl) {
    return Container(
      color: Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image, color: Colors.grey, size: 32),
          Text(
            '图片加载失败',
            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () {
              setState(() {}); // 触发重绘重试加载
            },
            child: const Text('重试',
                style: TextStyle(fontSize: 12, color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  // 在_SearchYiPageState类中添加以下方法

  void _handleImageTap(Plugin plugin, String resultUrl) {
    String url = '';
    if (resultUrl.isNotEmpty) {
      // 处理URL拼接逻辑
      if (resultUrl.startsWith('http://') || resultUrl.startsWith('https://')) {
        url = resultUrl;
      } else if (plugin.baseUrl.isNotEmpty) {
        if (plugin.baseUrl.endsWith('/') && resultUrl.startsWith('/')) {
          url = plugin.baseUrl + resultUrl.substring(1);
        } else if (!plugin.baseUrl.endsWith('/') &&
            !resultUrl.startsWith('/')) {
          url = '${plugin.baseUrl}/$resultUrl';
        } else {
          url = plugin.baseUrl + resultUrl;
        }
      }
    }

    // 如果URL有效则显示对话框
    if (url.isNotEmpty) {
      KazumiDialog.show(builder: (context) {
        return AlertDialog(
          title: const Text('打开链接'),
          content: Text('是否在浏览器中打开：\n$url'),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                KazumiDialog.dismiss();
                // 检查URL是否可打开
                if (await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication);
                } else {
                  // 处理无法打开URL的情况
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('无法打开链接：$url')),
                  );
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      });
    } else {
      // 处理无效URL的情况
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的链接地址')),
      );
    }
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
