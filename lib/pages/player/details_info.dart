import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/card/episode_comments_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/video/video_controller.dart';

import '../../bean/card/bangumi_info_card.dart';
import '../../bean/card/network_img_layer.dart';
import '../../bean/widget/embedded_native_control_area.dart';
import '../../request/bangumi.dart';
import '../history/history_controller.dart';

class DetailsCommentsSheet extends StatefulWidget {
  const DetailsCommentsSheet({super.key});

  @override
  State<DetailsCommentsSheet> createState() => _DetailsCommentsSheetState();
}

class _DetailsCommentsSheetState extends State<DetailsCommentsSheet> {
  final VideoPageController videoPageController =
      Modular.get<VideoPageController>();
  final HistoryController historyController = Modular.get<HistoryController>();

  // 新增：保存当前的bangumiItem状态（用于触发UI刷新）
  late BangumiItem _currentBangumiItem;

  // 新增：控制简介展开/收起状态
  bool _isExpanded = false;

  // 新增：控制标签展开/收起状态
  bool _showAllTags = false;

  @override
  void initState() {
    super.initState();
    _currentBangumiItem = videoPageController.bangumiItem;
  }

  // 计算文本在指定宽度下的行数（用于判断简介是否需要折叠）
  Future<int> _calculateTextLines(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth,
  ) async {
    await Future.delayed(const Duration(milliseconds: 10)); // 等待布局完成

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: null,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    return textPainter.computeLineMetrics().length;
  }

  // 修改：detailsBar读取当前状态的_bangumiItem（而非直接读控制器）
  Widget get detailsBar {
    return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 显示当前状态的bangumiId
                  Text('BangumiId:${_currentBangumiItem.id.toString()}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline)),
                  // 显示当前状态的剧名
                  Text(
                      (videoPageController.episodeInfo.nameCn != '')
                          ? '剧名:${_currentBangumiItem.nameCn}'
                          : '剧名:${_currentBangumiItem.name}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 34,
              child: TextButton(
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(
                      const EdgeInsets.only(left: 4.0, right: 4.0)),
                ),
                onPressed: () {
                  showBangumiItemSelection();
                },
                child: const Text(
                  '手动切换',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ));
  }

  // 构建评分星星显示（保留原有逻辑）
  Widget _buildRatingStars(double rating) {
    return Row(
      children: List.generate(5, (index) {
        double starValue = (index + 1) * 2;
        return Icon(
          starValue <= rating
              ? Icons.star
              : starValue - 1 <= rating
                  ? Icons.star_half
                  : Icons.star_border,
          color: Colors.amber,
          size: 16,
        );
      }),
    );
  }

  // 优化：评分分布改为「5组竖向柱状图」（保留原有逻辑）
  Widget _buildRatingDistribution(List<int> votesCount) {
    if (votesCount.isEmpty) return const SizedBox.shrink();

    final int total = votesCount.fold(0, (sum, item) => sum + item);
    if (total == 0) return const SizedBox.shrink();

    final List<Map<String, dynamic>> ratingGroups = [
      {'range': '10-9', 'count': votesCount[0] + votesCount[1]},
      {'range': '8-7', 'count': votesCount[2] + votesCount[3]},
      {'range': '6-5', 'count': votesCount[4] + votesCount[5]},
      {'range': '4-3', 'count': votesCount[6] + votesCount[7]},
      {'range': '2-1', 'count': votesCount[8] + votesCount[9]},
    ];

    final double maxPercentage = ratingGroups
        .map((group) => (group['count'] / total) * 100)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '评分分布',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: ratingGroups.map((group) {
            final double percentage = (group['count'] / total) * 100;
            final double barHeight =
                maxPercentage > 0 ? (percentage / maxPercentage) * 120 : 0;

            return Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    group['range'],
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // 优化：标签默认显示前3个，点击「更多」展开全部（保留原有逻辑）
  Widget _buildTags(List<BangumiTag> tags) {
    if (tags.isEmpty) return const SizedBox.shrink();

    final List<Widget> tagWidgets = [];
    final int displayCount =
        _showAllTags ? tags.length : (tags.length > 6 ? 6 : tags.length);

    for (int i = 0; i < displayCount; i++) {
      tagWidgets.add(
        Chip(
          label: Text(
            tags[i].name,
            style: const TextStyle(fontSize: 12),
          ),
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      );
    }

    if (tags.length > 3) {
      tagWidgets.add(
        TextButton(
          onPressed: () => setState(() => _showAllTags = !_showAllTags),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(20, 20),
          ),
          child: Chip(
            label: Text(
              _showAllTags ? '收起' : '更多(${tags.length - 3})',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '标签',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tagWidgets,
        ),
      ],
    );
  }

  // 构建别名列表（保留原有逻辑）
  Widget _buildAliases(List<String> aliases) {
    if (aliases.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '别名',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: aliases.map((alias) {
            return Text(
              alias,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // 修改：detailsBody读取当前状态的_bangumiItem（通过DetailsInfo传递）
  Widget get detailsBody {
    final BangumiItem bangumiItem = _currentBangumiItem; // 直接用当前状态的对象
    final String mainImage = bangumiItem.images.isNotEmpty
        ? bangumiItem.images['large'] ?? bangumiItem.images.values.first
        : '';
    final double introMaxWidth = MediaQuery.of(context).size.width - 32;

    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部封面和基本信息（使用当前状态的bangumiItem）
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mainImage.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: NetworkImgLayer(
                      src: mainImage,
                      width: 120,
                      height: 180,
                    ),
                  )
                else
                  Container(
                    width: 120,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.image_not_supported, size: 40),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bangumiItem.nameCn.isNotEmpty
                            ? bangumiItem.nameCn
                            : bangumiItem.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (bangumiItem.nameCn.isNotEmpty &&
                          bangumiItem.name != bangumiItem.nameCn)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            bangumiItem.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            bangumiItem.ratingScore.toString(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildRatingStars(bangumiItem.ratingScore),
                              const SizedBox(height: 4),
                              Text(
                                '${bangumiItem.votes} 人评分',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (bangumiItem.rank > 0)
                        Text(
                          '排名: #${bangumiItem.rank}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '播出日期: ${bangumiItem.airDate}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '播出星期: ${_getWeekdayName(bangumiItem.airWeekday)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 简介折叠功能（使用当前状态的bangumiItem）
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '简介',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  bangumiItem.summary.isNotEmpty
                      ? bangumiItem.summary
                      : '暂无简介信息',
                  style: const TextStyle(fontSize: 15, height: 1.6),
                  maxLines: _isExpanded ? null : 3,
                  overflow: _isExpanded ? null : TextOverflow.ellipsis,
                ),
                if (bangumiItem.summary.isNotEmpty)
                  FutureBuilder<int>(
                    future: _calculateTextLines(
                      context,
                      bangumiItem.summary,
                      const TextStyle(fontSize: 15, height: 1.6),
                      introMaxWidth,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data! > 3) {
                        return TextButton(
                          onPressed: () =>
                              setState(() => _isExpanded = !_isExpanded),
                          child: Text(
                            _isExpanded ? '收起简介' : '展开简介',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
              ],
            ),

            const SizedBox(height: 24),
            _buildTags(bangumiItem.tags),
            const SizedBox(height: 24),
            _buildAliases(bangumiItem.alias),
            const SizedBox(height: 24),
            _buildRatingDistribution(bangumiItem.votesCount),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // 将星期数字转换为中文名称（保留原有逻辑）
  String _getWeekdayName(int weekday) {
    switch (weekday) {
      case 0:
        return '星期日';
      case 1:
        return '星期一';
      case 2:
        return '星期二';
      case 3:
        return '星期三';
      case 4:
        return '星期四';
      case 5:
        return '星期五';
      case 6:
        return '星期六';
      default:
        return '未知';
    }
  }

  void showBangumiItemSelection() {
    // 1. 用 ValueNotifier 管理弹窗内所有状态（仅触发必要重绘，无 StatefulBuilder）
    final TextEditingController textController = TextEditingController();
    final ValueNotifier<List<BangumiItem>> _searchResults = ValueNotifier([]);
    final ValueNotifier<bool> _isLoading = ValueNotifier(false);
    final ValueNotifier<bool> _hasSearched = ValueNotifier(false);

    // 2. 搜索逻辑：独立函数，仅更新 ValueNotifier（不直接操作弹窗UI）
    Future<void> _doSearch() async {
      final keyword = textController.text.trim();
      if (keyword.isEmpty) {
        KazumiDialog.showToast(message: '请输入bangumi名称');
        return;
      }

      _isLoading.value = true;
      _hasSearched.value = true;

      try {
        // 调用搜索API
        final results = await BangumiHTTP.bangumiSearch(
          keyword,
          tags: [],
          offset: 0,
          sort: 'heat',
        );
        // 仅更新结果状态（由 ValueListenableBuilder 触发列表重绘）
        _searchResults.value = results;
      } catch (e) {
        KazumiDialog.showToast(message: '搜索失败，请重试');
        _searchResults.value = [];
      } finally {
        _isLoading.value = false;
      }
    }

    // 3. 选择逻辑：关闭弹窗→延迟→更新页面（确保弹窗完全销毁）
    void _onSelect(BangumiItem item) {
      // 第一步：立即关闭弹窗
      KazumiDialog.dismiss();

      // 第二步：延迟150ms（确保弹窗动画/渲染树完全清理）
      Future.delayed(const Duration(milliseconds: 150), () {
        // 避免重复选择
        if (item.id == _currentBangumiItem.id) {
          KazumiDialog.showToast(message: '已选择当前bangumi');
          return;
        }
        item.images = videoPageController.bangumiItem.images;
        item.name = videoPageController.bangumiItem.name;
        // 更新历史记录
        historyController.updateHistoryByKey(
          videoPageController.currentPlugin.name,
          _currentBangumiItem,
          item,
        );

        // 第三步：更新页面状态（此时弹窗已销毁，无渲染冲突）
        setState(() {
          videoPageController.bangumiItem = item;
          _currentBangumiItem = item;
        });
      });
    }

    // 4. 构建弹窗：用 ValueListenableBuilder 包裹局部UI（仅局部重绘）
    KazumiDialog.show(
      builder: (context) {
        // 禁用弹窗过渡动画（减少渲染时序冲突，关键！）
        return Dialog(
          elevation: 2,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                const Text('搜索bangumi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // 搜索输入框（无状态，仅触发搜索）
                TextField(
                  controller: textController,
                  decoration: const InputDecoration(
                    hintText: '输入bangumi名称',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _doSearch(),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),

                // 加载状态（仅加载时重绘）
                ValueListenableBuilder(
                  valueListenable: _isLoading,
                  builder: (context, isLoading, child) {
                    if (isLoading) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              CircularProgressIndicator(strokeWidth: 2),
                              SizedBox(height: 8),
                              Text('正在搜索...', style: TextStyle(fontSize: 14)),
                            ],
                          ),
                        ),
                      );
                    }
                    return child!;
                  },
                  child: ValueListenableBuilder(
                    valueListenable: _hasSearched,
                    builder: (context, hasSearched, child) {
                      // 未搜索时不显示结果区
                      if (!hasSearched) return const SizedBox.shrink();

                      // 搜索结果列表（仅结果变化时重绘）
                      return ValueListenableBuilder(
                        valueListenable: _searchResults,
                        builder: (context, results, _) {
                          // 无结果
                          if (results.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('未找到匹配结果，请换关键词', style: TextStyle(fontSize: 14, color: Colors.grey)),
                              ),
                            );
                          }

                          // 结果列表（简化Item，避免复杂组件）
                          return ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 280),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: results.length,
                              itemBuilder: (context, index) {
                                final item = results[index];
                                final imgUrl = item.images.isNotEmpty
                                    ? item.images['small'] ?? item.images.values.first
                                    : '';

                                return ListTile(
                                  leading: imgUrl.isNotEmpty
                                      ? ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    // 简化图片组件：用Image.network+错误占位，避免自定义NetworkImgLayer的潜在冲突
                                    child: Image.network(
                                      imgUrl,
                                      width: 40,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 24),
                                      loadingBuilder: (_, child, progress) => progress == null
                                          ? child
                                          : const SizedBox(width: 40, height: 56, child: CircularProgressIndicator(strokeWidth: 1)),
                                    ),
                                  )
                                      : const SizedBox(width: 40, height: 56, child: Icon(Icons.image_not_supported, size: 24)),
                                  title: Text(
                                    item.nameCn.isNotEmpty ? item.nameCn : item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    'ID: ${item.id}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  onTap: () => _onSelect(item), // 仅触发选择逻辑，无弹窗内状态更新
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 底部按钮（无状态，仅触发搜索/关闭）
                // 底部按钮（修正 onPressed 类型问题）
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => KazumiDialog.dismiss(),
                      child: Text('取消', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder(
                      valueListenable: _isLoading,
                      builder: (context, isLoading, _) {
                        return TextButton(
                          // 推荐用箭头函数包装，显式声明“无参数”，避免类型歧义
                          onPressed: isLoading ? null : () => _doSearch(),
                          child: const Text('搜索'),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }



  // 关键修改：用_currentBangumiItem更新DetailsInfo，确保子Widget同步刷新
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [detailsBar, detailsBody],
      ),
    );
  }
}
