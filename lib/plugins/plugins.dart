import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/request/request.dart';
import 'package:html/parser.dart';
import 'package:logger/logger.dart';
import 'package:kazumi/utils/logger.dart';
import 'package:path/path.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

class Plugin {
  String api;
  String type;
  String name;
  String version;
  bool muliSources;
  bool useWebview;
  bool useNativePlayer;
  bool usePost;
  bool useLegacyParser;
  String userAgent;
  String baseUrl;
  String searchURL;
  String searchImg;
  String searchList;
  String searchName;
  String searchResult;
  String chapterRoads;
  String chapterItems;
  String chapterResult;
  String chapterResultName;
  String referer;
  Map<String, String> tags;
  Map<String, String> keywords;

  Plugin({
    required this.api,
    required this.type,
    required this.name,
    required this.version,
    required this.muliSources,
    required this.useWebview,
    required this.useNativePlayer,
    required this.usePost,
    required this.useLegacyParser,
    required this.userAgent,
    required this.baseUrl,
    required this.searchURL,
    required this.searchList,
    required this.searchName,
    this.searchImg = '',
    required this.searchResult,
    required this.chapterRoads,
    this.chapterItems = '',
    required this.chapterResult,
    this.chapterResultName = '',
    required this.referer,
    required this.tags,
    required this.keywords,
  });

  factory Plugin.fromJson(Map<String, dynamic> json) {
    return Plugin(
        api: json['api'],
        type: json['type'],
        name: json['name'],
        version: json['version'],
        muliSources: json['muliSources'],
        useWebview: json['useWebview'],
        useNativePlayer: json['useNativePlayer'],
        usePost: json['usePost'] ?? false,
        useLegacyParser: json['useLegacyParser'] ?? false,
        userAgent: json['userAgent'],
        baseUrl: json['baseURL'],
        searchURL: json['searchURL'],
        searchList: json['searchList'],
        searchName: json['searchName'],
        searchImg: json['searchImg'] ?? '',
        searchResult: json['searchResult'],
        chapterRoads: json['chapterRoads'],
        chapterItems: json['chapterItems'] ?? '',
        chapterResult: json['chapterResult'],
        chapterResultName: json['chapterResultName'] ?? '',
        referer: json['referer'] ?? '',
        tags: Map<String, String>.from(json['tags'] ?? {}),
        keywords: {}); // 添加tags字段
  }

  factory Plugin.fromTemplate() {
    return Plugin(
      api: '1',
      type: 'anime',
      name: '',
      version: '',
      muliSources: true,
      useWebview: true,
      useNativePlayer: false,
      usePost: false,
      useLegacyParser: false,
      userAgent: '',
      baseUrl: '',
      searchURL: '',
      searchList: '',
      searchName: '',
      searchImg: '',
      searchResult: '',
      chapterRoads: '',
      chapterItems: '',
      chapterResult: '',
      chapterResultName: '',
      referer: '',
      tags: {},
      keywords: {},
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['api'] = api;
    data['type'] = type;
    data['name'] = name;
    data['version'] = version;
    data['muliSources'] = muliSources;
    data['useWebview'] = useWebview;
    data['useNativePlayer'] = useNativePlayer;
    data['usePost'] = usePost;
    data['useLegacyParser'] = useLegacyParser;
    data['userAgent'] = userAgent;
    data['baseURL'] = baseUrl;
    data['searchURL'] = searchURL;
    data['searchList'] = searchList;
    data['searchName'] = searchName;
    data['searchImg'] = searchImg;
    data['searchResult'] = searchResult;
    data['chapterRoads'] = chapterRoads;
    data['chapterItems'] = chapterItems;
    data['chapterResult'] = chapterResult;
    data['chapterResultName'] = chapterResultName;
    data['referer'] = referer;
    data['tags'] = tags;
    return data;
  }

  Future<Map<String, String>> queryTags() async {

    if (tags.isNotEmpty) {
      final urlPattern = RegExp(r'@url\[(.*?)\]', caseSensitive: false);
      final xpathPattern = RegExp(
        r'@xpath\[((?:[^[\]]|\[.*?\])*)\]',
        caseSensitive: false,
        multiLine: true,
      );

      // 使用异步循环处理每个tag
      await Future.forEach(tags.entries, (entry) async {
        final key = entry.key;
        final value = entry.value;

        try {
          final urlMatch = urlPattern.firstMatch(value);
          final xpathMatch = xpathPattern.firstMatch(value);

          if (urlMatch != null && xpathMatch != null) {
            final url = urlMatch.group(1)!.trim();
            final xpath = xpathMatch.group(1)!.trim();
            print(xpath);

            if (url.isNotEmpty && xpath.isNotEmpty) {
              final resp = await Request().get(
                url,
                options: Options(headers: {'referer': '$baseUrl/'}),
                shouldRethrow: false,
                extra: {'customError': ''},
              );
              final htmlString =resp.data.toString();
              final htmlElement = parse(htmlString).documentElement!;
              if(getResultType(xpath)==XPathResultType.attribute){
                keywords[key] = htmlElement.queryXPath(xpath).attrs.firstOrNull ?? '';
              }else if(getResultType(xpath)==XPathResultType.text){
                keywords[key] = htmlElement.queryXPath(xpath).node?.text ?? '';
              }else{
                keywords[key]='';
              }
            }
          }
        } catch (e) {
          debugPrint('解析失败 [$key]: ${e.toString()}');
          keywords[key] = '解析错误';
        }
      });
    }

    return keywords;
  }

  String replaceTag(String queryURL) {
    final tagPattern = RegExp(r'@tag\[(.*?)\]', caseSensitive: false);

    // 使用 replaceAllMapped 一次性替换所有匹配项
    queryURL = queryURL.replaceAllMapped(tagPattern, (Match match) {
      final tagName = match.group(1)!.trim(); // 提取标签名并去除两端空格
      print(keywords);
      print(keywords[tagName]);
      return Uri.encodeComponent(keywords[tagName] ?? ''); // 替换为编码后的值，不存在则返回空
    });
    return queryURL;
  }

  Future<PluginSearchResponse> queryBangumi(String keyword,
      {bool shouldRethrow = false, int page = 1}) async {
    await queryTags();
    String queryURL = searchURL.replaceAll('@keyword', keyword);
    if (queryURL.contains('@pagenum')) {
      queryURL = queryURL.replaceAll('@pagenum', page > 0 ? page.toString() : '1');
    }
    queryURL = replaceTag(queryURL);
    dynamic resp;
    List<SearchItem> searchItems = [];
    if (usePost) {
      Uri uri = Uri.parse(queryURL);
      Map<String, String> queryParams = uri.queryParameters;
      Uri postUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        path: uri.path,
      );
      var httpHeaders = {
        'referer': '$baseUrl/',
        'Content-Type': 'application/x-www-form-urlencoded',
      };
      resp = await Request().post(postUri.toString(),
          options: Options(headers: httpHeaders),
          extra: {'customError': ''},
          data: queryParams,
          shouldRethrow: shouldRethrow);
    } else {
      var httpHeaders = {
        'referer': '$baseUrl/',
      };
      resp = await Request().get(queryURL,
          options: Options(headers: httpHeaders),
          shouldRethrow: shouldRethrow,
          extra: {'customError': ''});
    }

    var htmlString = resp.data.toString();
    var htmlElement = parse(htmlString).documentElement!;

    htmlElement.queryXPath(searchList).nodes.forEach((element) {
      try {
        final pattern = RegExp(
            r'^(.*?)\s*@start-xpath\s+(.*?)\s+@end-xpath\s*(.*)$',
            multiLine: false,
            caseSensitive: false);
        final match = pattern.firstMatch(searchImg);
        var fullImgUrl = '';
        if (match != null) {
          final prefix =
              match.group(1)?.trim() ?? ''; // 第一部分：@start-xpath 之前的内容
          final xpath = match.group(2)?.trim() ?? ''; // 第二部分：中间的 XPath
          final suffix = match.group(3)?.trim() ?? ''; // 第三部分：@end-xpath 之后的内容
          // 构建完整图片 URL
          final relativePath =
              element.queryXPath(xpath).attrs.firstOrNull ?? '';
          fullImgUrl = '$prefix$relativePath$suffix';
        } else {
          fullImgUrl = element.queryXPath(searchImg).attrs.firstOrNull ?? '';
        }
        SearchItem searchItem = SearchItem(
          name: (element.queryXPath(searchName).node!.text ?? '')
              .replaceAll(RegExp(r'\s+'), ' ') // 将连续空白替换为单个空格
              .trim(), // 去除首尾空格
          img: fullImgUrl ?? '',
          src: element.queryXPath(searchResult).node!.attributes['href'] ?? '',
        );
        searchItems.add(searchItem);
        KazumiLogger().log(Level.info,
            '$name ${element.queryXPath(searchName).node!.text ?? ''} $baseUrl${element.queryXPath(searchResult).node!.attributes['href'] ?? ''}');
      } catch (_) {}
    });
    PluginSearchResponse pluginSearchResponse =
        PluginSearchResponse(pluginName: name, data: searchItems);
    return pluginSearchResponse;
  }

  Future<List<Road>> querychapterRoads(String url) async {
    List<Road> roadList = [];
    // 预处理
    if (!url.contains('https')) {
      url = url.replaceAll('http', 'https');
    }
    String queryURL = '';
    if (url.contains(baseUrl)) {
      queryURL = url;
    } else {
      queryURL = baseUrl + url;
    }
    var httpHeaders = {
      'referer': '$baseUrl/',
    };
    try {
      var resp =
          await Request().get(queryURL, options: Options(headers: httpHeaders));
      var htmlString = resp.data.toString();
      var htmlElement = parse(htmlString).documentElement!;
      int count = 1;
      htmlElement.queryXPath(chapterRoads).nodes.forEach((element) {
        try {
          List<String> chapterUrlList = [];
          List<String> chapterNameList = [];
          element.queryXPath(chapterItems).nodes.forEach((item) {
            String itemUrl =
                item.queryXPath(chapterResult).node!.attributes['href'] ?? '';
            String itemName = '';
            itemName = item.queryXPath(chapterResultName).node?.text ?? '';
            chapterUrlList.add(itemUrl);
            chapterNameList.add(itemName.replaceAll(RegExp(r'\s+'), ''));
          });
          if (chapterUrlList.isNotEmpty && chapterNameList.isNotEmpty) {
            Road road = Road(
                name: '播放列表$count',
                data: chapterUrlList,
                identifier: chapterNameList);
            roadList.add(road);
            count++;
          }
        } catch (_) {}
      });
    } catch (_) {}
    return roadList;
  }
}

enum XPathResultType {
  attribute,
  text
}

XPathResultType getResultType(String xpath) {
  if (xpath.endsWith('/text()')) return XPathResultType.text;
  return XPathResultType.attribute;
}
