# mangaga 运行环境需求

## 必须环境

- Windows 10/11。
- Windows PowerShell 5.1。
- .NET Framework / WPF 运行环境，需能加载 `PresentationFramework`、`PresentationCore`、`WindowsBase`、`System.Windows.Forms`。
- Python 3.10 或更高版本，建议 Python 3.12。
- Python 包：`Pillow`。

## 压缩包支持

- `.zip`：使用 Python 标准库，无额外工具。
- `.rar` / `.7z`：建议安装 7-Zip，并确保可执行文件为以下任一形式：
  - `7z.exe`
  - `7zz.exe`
  - `7za.exe`
- 如果未安装 7-Zip，程序会尝试使用 Windows 自带 `tar.exe`，但兼容性不如 7-Zip。

## 可选 OCR 功能

作品名识别需要额外安装：

- `paddleocr`
- `paddlepaddle`
- `manga-ocr`
- `torch`
- `transformers`

OCR 模型文件不随本工具发布。首次使用时由用户自行在软件提示的初始化流程中允许 PaddleOCR 下载并缓存模型。
软件会在首次手动开始作品名识别时检查 OCR 状态，并把用户选择保存到 `data/settings.json`。

## 可选联网 Tag 功能

自动 Tag 识别会访问用户主动配置或触发的站点，例如 EH/ExHentai、WNACG。

- 基础 HTTP 请求使用 Python 标准库 `urllib`。
- EH/ExHentai Cookie 不应写入源码仓库。
- EhTagTranslation 翻译库不随纯净版内置。首次使用 Tag 翻译时，用户可选择下载到 `data/ehtag-translation/db.text.json`、使用在线翻译或不翻译。
- Tag 翻译选择写入 `data/settings.json`。
