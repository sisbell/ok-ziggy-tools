This is a build tool for creating a catalog intended for consumption by large language model chatbots.

# Usage
## Install This tool
Make sure your have dart installed. Follow the instructions, in the link below.

https://dart.dev/get-dart

After installation, you can install the tools with the following command

> dart pub global activate ok_ziggy_tools

## Create the Catalog
```
Creates the catalog

Usage: zigt create [arguments]
-h, --help     Print this usage information.
-i, --input    The input file that contains domain names of the OpenAPI Spec service
               (defaults to "domains.json")
```
The build generates a number of files including error logs. You will use some of these when
constructing the chatbot server.

<img width="331" alt="build" src="https://github.com/sisbell/ok-ziggy-tools/assets/64116/dc593400-9452-4999-8980-1d943f9a3e33">

## Copy
```
Copies the catalog files to a target directory

Usage: zigt copy [arguments]
-h, --help         Print this usage information.
-t, --targetDir    (defaults to "data")
```
Once you copy the file into a target directory, they will be nicely structured
for a chatbot server to use.

<img width="340" alt="copy" src="https://github.com/sisbell/ok-ziggy-tools/assets/64116/6e868682-36f6-45ab-97e4-b682c679e3cc">


# Input File
The input file is just a list of domains hosting manifests. The tool will look for an ai-plugin.json manifest at
the domain and then build a catalog entry for it.

```json
[
  "ai.abcmouse.com",
  "api.speak.com",
  "chatwithpdf.sdan.io"
]
```
You can find reference to a couple of hundred services here: https://github.com/sisbell/chatgpt-plugin-store

# Generated Files
There are two types of information that a chatbot needs to learn about services to provide to a user
1. **List of services** - this describes what's available and allows the chatbot to decide what service to use based on client interation
2. **Specifications** - this describes each endpoint and how to use and store remote data.

## Services
This is the primary service catalog that is used to advertise services to a chatbot.
```json
[
  {
    "serviceId": "ff57602e9b",
    "name": "ABCmouse",
    "description": "Provides fun and educational learning activities for children 2-8 years old."
  },
  {
    "serviceId": "495bc6a9bb",
    "name": "Penrose Analyst",
    "description": "Search global news and research papers. Summarize Arxiv.org links. Ask me for the latest news!"
  },
  {
    "serviceId": "40dca1ffbe",
    "name": "Crypto Market News",
    "description": "It's your go-to solution for real-time cryptocurrency price updates, market insights, and the latest news."
  }
]
```
## Spec Files
For each service there will be a spec file generated. It consists of two parts. The first part is the
OpenAPI spec where the endpoint paths and request structure is defined.

The second part is the
**EXTRA_INFORMATION_TO_ASSISTANT.** This is the _description_for_model_ field from the AI manifest.

```yaml
openapi: "3.0.0"
info:
  version: "1.0.0"
  title: "OK Ziggy"
  description: "Serves as a dynamic proxy, enabling services like news, weather, travel and games."
servers:
  - url: "httos://ziggy.zapvine.com/api/v1"
paths:
  /services:
    get:
      summary: Retrieve a list of available services
      operationId: "getServices"
      responses:
        "200":
          description: Successful operation
  # Rest of spec

EXTRA_INFORMATION_TO_ASSISTANT
  The AI assistant's name is Ziggy. Ziggy's main job..[rest of prompt instruction] 
```

## Chatbot Server Config Files
The following files are configuration files that a chatbot server uses to provide services

### API Map
This maps the serviceId to the URL of the api server.
```json
{
  "ff57602e9b": "ai.abcmouse.com/ws/ai/0.1/gpt",
  "a3be2a6602": "api.speak.com",
  "2d59d0bd16": "chatwithpdf.sdan.io",
  "5742d3c9b4": "openai.jettel.de",
  "7da6597eed": "plugin.askyourpdf.com"
}
```

### Domain Map
This maps the service id to the domain that hosts the manifest. This domain considered the unique id of the service.
```json
{
  "ff57602e9b": "ai.abcmouse.com",
  "a3be2a6602": "api.speak.com",
  "2d59d0bd16": "chatwithpdf.sdan.io"
}
```
### Content Types
This maps a service path to a content-type.
```json
{
"ff57602e9b/ChatPluginRecommendActivities": "application/json",
"a3be2a6602/translate": "application/json",
"a3be2a6602/explainPhrase": "application/json",
"a3be2a6602/explainTask": "application/json",
"2d59d0bd16/loadPdf": "application/json"
}
```

