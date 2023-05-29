import 'package:args/command_runner.dart';
import 'package:file/local.dart';
import 'package:ok_ziggy_tools/ok_ziggy_tools.dart';

final localFileSystem = LocalFileSystem();

void main(List<String> arguments) async {
  CommandRunner("zigt",
      "A build tool for creating a catalog intended for consumption by large language model chatbots")
    ..addCommand(BuildCatalogCommand())
    ..addCommand(CopyCatalogCommand())
    ..run(arguments);
}

class BuildCatalogCommand extends Command {
  @override
  String get description => "Creates the catalog";

  @override
  String get name => "create";

  BuildCatalogCommand() {
    argParser.addOption('input',
        abbr: 'i',
        defaultsTo: "domains.json",
        help:
            "The input file that contains domain names of the OpenAPI Spec service");
  }

  @override
  Future<void> run() async {
    final inputFileName = localFileSystem.file(argResults?["input"]);
    final tool = BuildTool(localFileSystem, "build");
    await tool.buildCatalog(inputFileName);
  }
}

class CopyCatalogCommand extends Command {
  @override
  String get description => "Copies the catalog files to a target directory";

  @override
  String get name => "copy";

  CopyCatalogCommand() {
    argParser.addOption('targetDir', abbr: 't', defaultsTo: "data");
  }

  @override
  Future<void> run() async {
    final targetDirectory = argResults?["targetDir"];
    final tool = BuildTool(LocalFileSystem(), "build");
    await tool.copyCatalog(targetDirectory);
  }
}
