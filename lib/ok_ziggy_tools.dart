import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class BuildTool {
  final String buildDir;

  final encoder = JsonEncoder.withIndent('  ');

  final FileSystem fileSystem;

  late final File apiMapFile;

  late final File contentTypesFile;

  late final File domainMapFile;

  late final String manifestsDir;

  late final File servicesFile;

  late final String specsDir;

  BuildTool(this.fileSystem, this.buildDir) {
    manifestsDir = "$buildDir/manifests";
    specsDir = "$buildDir/specs";
    domainMapFile = fileSystem.file("$buildDir/domain-map.json");
    apiMapFile = fileSystem.file('$buildDir/api-map.json');
    contentTypesFile = fileSystem.file('$buildDir/content-types.json');
    servicesFile = fileSystem.file('$buildDir/services.json');
  }

  Future<void> buildCatalog(domainsFile) async {
    deleteBuildDirectory();
    final domainFile = fileSystem.file(domainsFile);
    final domains = (jsonDecode(await domainFile.readAsString()) as List)
        .map((item) => item as String)
        .toList();
    await _downloadCatalog(domains);
    final serviceMap = await _generateUuidsForDomains(domains);
    await _generateServiceJson(serviceMap);
    await _extractAndWriteContentTypes();
    await _extractAndWriteProxyMap();
    await addInfoToAssistant();
  }

  Future<void> deleteBuildDirectory() async {
    final dir = fileSystem.directory(buildDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> copyCatalog(targetDirectory) async {
    final buildSpecsDir = fileSystem.directory(specsDir);
    final dataCatalogDir = fileSystem.directory('$targetDirectory/catalog');
    final dataCatalogSpecsDir =
        fileSystem.directory('$targetDirectory/catalog/specs');

    if (await dataCatalogDir.exists()) {
      await dataCatalogDir.delete(recursive: true);
    }

    await dataCatalogSpecsDir.create(recursive: true);
    final specsFiles = buildSpecsDir.listSync();
    for (var file in specsFiles) {
      if (file is File) {
        await file.copy('${dataCatalogSpecsDir.path}/${file.basename}');
      }
    }
    await copyFileIfExists(servicesFile.path, dataCatalogDir.path);
    await copyFileIfExists(domainMapFile.path, dataCatalogDir.path);
    await copyFileIfExists(contentTypesFile.path, dataCatalogDir.path);
    await copyFileIfExists(apiMapFile.path, dataCatalogDir.path);
  }

  Future<void> copyFileIfExists(String inputFilePath, String outputDir) async {
    var inputFile = io.File(inputFilePath);
    if (await inputFile.exists()) {
      final outputFileName = p.basename(inputFilePath);
      final outputFile = p.join(outputDir, outputFileName);
      await inputFile.copy(outputFile);
    } else {
      print("Unable to copy file: $inputFilePath");
    }
  }

  Future<void> addInfoToAssistant() async {
    final manifestDirectory = fileSystem.directory(manifestsDir);
    final specDirectory = fileSystem.directory(specsDir);
    for (var file in manifestDirectory.listSync().whereType<File>()) {
      if (file.path.endsWith('.json')) {
        final jsonContent = json.decode(await file.readAsString());
        var domain = file.uri.pathSegments.last;
        domain = domain.substring(0, domain.lastIndexOf('.'));
        final description = jsonContent['description_for_model'];
        final specFileYaml =
            fileSystem.file('${specDirectory.path}/$domain.yaml');
        final specFileJson =
            fileSystem.file(('${specDirectory.path}/$domain.json'));
        final specFile = specFileYaml.existsSync()
            ? specFileYaml
            : (specFileJson.existsSync() ? specFileJson : null);
        if (specFile != null) {
          await specFile.writeAsString(
              '\nEXTRA_INFORMATION_TO_ASSISTANT\n$description',
              mode: FileMode.append);
        }
      }
    }
  }

  Future<void> createDirectoryIfNotExist(String path) async {
    final dir = fileSystem.directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<void> _downloadCatalog(List<String> domains) async {
    await _processManifests(domains);
    await _processSpecs();
  }

  Future<void> _downloadData(List<Map<String, dynamic>> domains,
      {bool isManifest = false}) async {
    final outputDir = isManifest ? manifestsDir : specsDir;
    final start = DateTime.now().second;
    await createDirectoryIfNotExist(outputDir);
    var logData = {
      "failures": [],
    };

    for (var domainInfo in domains) {
      final domain = domainInfo['domain'];
      final url = isManifest
          ? Uri.parse('https://$domain/.well-known/ai-plugin.json')
          : Uri.parse(domainInfo['url']);
      try {
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final path = url.path;
          final isJson = path.endsWith('.json');
          final isYaml = path.endsWith('.yaml') || path.endsWith('.yml');
          final outputFile =
              fileSystem.file('$outputDir/$domain.${isJson ? 'json' : 'yaml'}');
          if (isJson) {
            final data = json.decode(response.body);
            await outputFile.writeAsString(encoder.convert(data));
          } else if (isYaml) {
            await outputFile.writeAsString(response.body);
          }
        } else {
          print(
              'Failed to load data for $domain. Response status: ${response.statusCode}');
          logData["failures"]!.add({
            "domain": domain,
            "responseCode": response.statusCode,
            "exception":
                'Failed to load data for $domain. Response status: ${response.statusCode}',
          });
        }
      } catch (e, s) {
        print('Exception occurred: $e');
        print('Stack trace: $s');
        logData["failures"]!.add({
          "domain": domain,
          "responseCode": null,
          "exception": e.toString(),
        });
      }
    }
    final duration = DateTime.now().second - start;
    print("Total Time: $duration seconds");
    final errorFile = isManifest
        ? '$buildDir/failures-manifest.json'
        : '$buildDir/failures-spec.json';
    final logFile = fileSystem.file(errorFile);
    await logFile.writeAsString(encoder.convert(logData));
  }

  Future<void> _generateServiceJson(Map<String, String> uuidServiceMap) async {
    final services = <Map<String, String>>[];
    final dir = fileSystem.directory(manifestsDir);
    final files = dir.listSync();
    for (var file in files) {
      if (p.extension(file.path) == '.json') {
        final domain = p.basenameWithoutExtension(file.path);
        final serviceId = uuidServiceMap.entries
            .firstWhere((entry) => entry.value == domain)
            .key;
        final content = fileSystem.file(file.path).readAsStringSync();
        final manifest = jsonDecode(content);
        services.add({
          'serviceId': serviceId,
          'name': manifest['name_for_human'],
          'description': manifest['description_for_human'],
        });
      }
    }
    servicesFile.writeAsStringSync(encoder.convert(services));
  }

  Future<Map<String, String>> _generateUuidsForDomains(
      List<String> domains) async {
    final uuidServiceMap = <String, String>{};
    for (var domain in domains) {
      var bytes = utf8.encode(domain);
      var digest = md5.convert(bytes);
      var id = digest.toString().substring(0, 10);
      uuidServiceMap[id] = domain;
    }
    domainMapFile.writeAsString(encoder.convert(uuidServiceMap));
    return uuidServiceMap;
  }

  Future<void> _processManifests(List<String> domains) async {
    final domainInfo = domains.map((domain) => {'domain': domain}).toList();
    await _downloadData(domainInfo, isManifest: true);
  }

  Future<void> _processSpecs() async {
    final dir = fileSystem.directory(manifestsDir);
    final files = dir
        .listSync()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>();

    final domains = <Map<String, String>>[];

    for (var file in files) {
      final content = await file.readAsString();
      final data = json.decode(content);
      final domain = p.basenameWithoutExtension(file.path);
      final url = data['api']['url'];
      domains.add({
        'domain': domain,
        'url': url,
      });
    }
    await _downloadData(domains);
  }

  Future<void> _extractAndWriteContentTypes() async {
    final serviceIdSpecs =
        jsonDecode(await domainMapFile.readAsString()) as Map<String, dynamic>;

    final contentTypes = <String, String>{};

    for (final entry in serviceIdSpecs.entries) {
      final serviceId = entry.key;
      final serviceName = entry.value as String;
      final jsonFile = fileSystem.file('$specsDir/$serviceName.json');
      final yamlFile = fileSystem.file('$specsDir/$serviceName.yaml');
      final isYaml = await yamlFile.exists();
      final specFile = isYaml ? yamlFile : jsonFile;
      if (await specFile.exists()) {
        final fileContent = await specFile.readAsString();
        contentTypes.addAll(
            await _extractContentTypes(serviceId, fileContent, isYaml: isYaml));
      } else {
        print("Did not find spec file: ${specFile.path}");
      }
    }

    await contentTypesFile.writeAsString(encoder.convert(contentTypes),
        mode: FileMode.write);
  }

  Future<void> _extractAndWriteProxyMap() async {
    final domainMap = await json.decode(await domainMapFile.readAsString());
    var apiMap = <String, String>{};

    for (var entry in domainMap.entries) {
      final serviceName = entry.value;
      final jsonFile = fileSystem.file('$specsDir/$serviceName.json');
      final yamlFile = fileSystem.file('$specsDir/$serviceName.yaml');
      final isYaml = await yamlFile.exists();
      final specFile = isYaml ? yamlFile : jsonFile;
      if (await specFile.exists()) {
        final fileContent = await specFile.readAsString();
        dynamic spec;
        if (isYaml) {
          spec = loadYaml(fileContent);
        } else {
          spec = jsonDecode(fileContent);
        }
        if (spec['servers'] != null && spec['servers'][0]['url'] != null) {
          var urlWithoutProtocol = spec['servers'][0]['url']
              .replaceAll(RegExp(r'^https?://|/$'), '');
          apiMap[entry.key] = urlWithoutProtocol;
        } else {
          apiMap[entry.key] = entry.value;
        }
      }
    }
    await apiMapFile.writeAsString(encoder.convert(apiMap));
  }

  Future<Map<String, String>> _extractContentTypes(
      String serviceId, String fileContent,
      {bool isYaml = false}) async {
    dynamic spec;
    if (isYaml) {
      spec = loadYaml(fileContent);
    } else {
      spec = jsonDecode(fileContent);
    }

    final paths = spec['paths'];
    final contentTypes = <String, String>{};

    paths.forEach((path, data) {
      final methods = data;
      methods.forEach((method, details) {
        final operationId = details['operationId'] as String;
        final requestBody = details['requestBody'];
        if (requestBody != null && requestBody['content'] != null) {
          final content = requestBody['content'];
          if (content.keys.isNotEmpty) {
            final contentType = content.keys.first;
            contentTypes['$serviceId/$operationId'] = contentType;
          }
        }
      });
    });
    return contentTypes;
  }

//
  Future<void> downloadAndUnzip(outputDirPath) async {
    final url =
        "https://storage.googleapis.com/zapvine-prod.appspot.com/ziggy/ok-ziggy-config.zip";
    var client = http.Client();
    var req = await client.get(Uri.parse(url));
    List<int> bytes = req.bodyBytes;
    Archive archive = ZipDecoder().decodeBytes(bytes);
    for (ArchiveFile file in archive) {
      String filename = file.name;
      if (file.isFile) {
        List<int> data = file.content;
        File outFile = fileSystem.file(p.join(outputDirPath, filename));
        outFile = await outFile.create(recursive: true);
        await outFile.writeAsBytes(data);
      } else {
        await io.Directory(p.join(outputDirPath, filename))
            .create(recursive: true);
      }
    }
  }
}
