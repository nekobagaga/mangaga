from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
import locale
import math
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import warnings
import zipfile
from collections import defaultdict
from datetime import datetime, timezone
from html import unescape
from pathlib import Path

from PIL import Image, ImageOps, ImageStat

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif"}
WPF_DIRECT_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".gif"}
ARCHIVE_EXTS = {".zip", ".rar", ".7z"}
SEVEN_ZIP_COMMON_PATHS = (
    Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "7-Zip" / "7z.exe",
    Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "7-Zip" / "7z.exe",
)
FAVORITE_CATEGORY = "喜爱"
LEGACY_FAVORITE_CATEGORY = "收藏"
PENDING_TITLE_CATEGORY = "待确认"
TITLE_RECOGNIZING_CATEGORY = "识别中"
PASSWORD_REQUIRED_CATEGORY = "需要密码"
DUPLICATE_CATEGORY = "重复项"
TAG_NOT_FOUND_CATEGORY = "tag未找到"
DEFAULT_CATEGORIES = ["热血", "恋爱", "悬疑"]
SYSTEM_CATEGORIES = {
    "全部",
    "未分类",
    FAVORITE_CATEGORY,
    PENDING_TITLE_CATEGORY,
    TITLE_RECOGNIZING_CATEGORY,
    PASSWORD_REQUIRED_CATEGORY,
    TAG_NOT_FOUND_CATEGORY,
    DUPLICATE_CATEGORY,
}
ASSIGNABLE_SYSTEM_CATEGORIES = {FAVORITE_CATEGORY, PENDING_TITLE_CATEGORY, TITLE_RECOGNIZING_CATEGORY}
USER_ASSIGNABLE_SYSTEM_CATEGORIES = {FAVORITE_CATEGORY}
MANAGED_TITLE_CATEGORIES = {PENDING_TITLE_CATEGORY, TITLE_RECOGNIZING_CATEGORY}
TITLE_STATUS_NONE = ""
TITLE_STATUS_RECOGNIZING = "recognizing"
TITLE_STATUS_PENDING = "pending"
TITLE_STATUS_BY_CATEGORY = {
    TITLE_RECOGNIZING_CATEGORY: TITLE_STATUS_RECOGNIZING,
    PENDING_TITLE_CATEGORY: TITLE_STATUS_PENDING,
}
TAG_STATUS_NONE = ""
TAG_STATUS_NOT_FOUND = "not_found"
TAG_TARGET_NAMESPACES = {"parody", "female", "male", "mixed"}
TAG_NAMESPACE_PRIORITY = ("parody", "female", "male", "mixed")
COVER_SIZE = (260, 370)
COVER_BACKGROUND = (32, 35, 42)
READER_BACKGROUND = (17, 19, 22)
READER_CONVERTED_IMAGE_EXT = ".jpg"
TITLE_SAMPLE_HEAD_COUNT = 5
TITLE_SAMPLE_TAIL_COUNT = 5
TITLE_CANDIDATE_LIMIT = 8
OCR_MAX_IMAGE_DIMENSION = 1600
PADDLE_OCR_LANG = "japan"
PADDLE_OCR_MIN_SCORE = 0.45
PADDLE_OCR_DETECTION_LIMIT = 256
PADDLE_OCR_DEFAULT_BATCH_SIZE = 5
IMPORT_FAVORITE_GUARD_SECONDS = 12
TAG_SCRAPE_MIN_DELAY_MS = 3000
TAG_SCRAPE_MAX_DELAY_MS = 5000
TAG_SEARCH_RESULT_LIMIT = 5
TAG_SEARCH_MAX_QUERY_COUNT = 2
TAG_SEARCH_STOP_SCORE = 85
EH_REQUEST_TIMEOUT_SECONDS = 15
EH_CACHE_MAX_AGE_SECONDS = 7 * 24 * 60 * 60
EH_DEFAULT_BASE_URL = "https://e-hentai.org"
EH_API_URL = "https://api.e-hentai.org/api.php"
TAG_MATCH_MIN_SCORE = 90
WNACG_DEFAULT_BASE_URL = "https://www.wnacg.com"
WNACG_REQUEST_TIMEOUT_SECONDS = 15
GOOGLE_TRANSLATE_URL = "https://translate.googleapis.com/translate_a/single"
TRANSLATE_REQUEST_TIMEOUT_SECONDS = 15
EHTAG_TRANSLATION_URL = "https://raw.githubusercontent.com/EhTagTranslation/DatabaseReleases/master/db.text.json"
EXTERNAL_ARCHIVE_LIST_TIMEOUT_SECONDS = 30
EXTERNAL_ARCHIVE_EXTRACT_TIMEOUT_SECONDS = 30
READER_INITIAL_CACHE_COUNT = 25
DUPLICATE_VISUAL_COVER_MAX_DISTANCE = 4
DUPLICATE_VISUAL_PAGE_MAX_DISTANCE = 8
DUPLICATE_VISUAL_AVG_MAX_DISTANCE = 3.0
DUPLICATE_VISUAL_FULL_CONFIRM_MAX_PAGES = 60
TAG_KIND = "tag"
MANUAL_CATEGORY_KIND = "manual"
TAG_NAMESPACE_TRANSLATIONS = {
    "artist": "作者",
    "character": "角色",
    "cosplayer": "Coser",
    "female": "女性",
    "group": "社团",
    "language": "语言",
    "male": "男性",
    "mixed": "混合",
    "other": "其他",
    "parody": "原作",
    "reclass": "类型",
}
EH_TAG_BLACKLIST: set[str] = set()
KNOWN_PARODY_SEEDS = {
    "东方": "touhou project",
    "東方": "touhou project",
    "touhou": "touhou project",
    "原神": "genshin impact",
    "genshin": "genshin impact",
    "崩坏星穹铁道": "honkai star rail",
    "崩壊スターレイル": "honkai star rail",
    "star rail": "honkai star rail",
    "崩坏3": "honkai impact 3rd",
    "崩壊3rd": "honkai impact 3rd",
    "碧蓝航线": "azur lane",
    "アズールレーン": "azur lane",
    "azur lane": "azur lane",
    "蔚蓝档案": "blue archive",
    "ブルーアーカイブ": "blue archive",
    "blue archive": "blue archive",
    "舰队collection": "kantai collection",
    "艦これ": "kantai collection",
    "fgo": "fate grand order",
    "fate grand order": "fate grand order",
}
TAG_TRADITIONAL_TO_SIMPLIFIED = str.maketrans(
    {
        "綁": "绑",
        "縛": "缚",
        "項": "项",
        "頭": "头",
        "顏": "颜",
        "雙": "双",
        "馬": "马",
        "長": "长",
        "襪": "袜",
        "貧": "贫",
        "體": "体",
        "變": "变",
        "膠": "胶",
        "緊": "紧",
        "蘿": "萝",
        "綠": "绿",
        "處": "处",
        "藥": "药",
        "書": "书",
        "庫": "库",
        "亂": "乱",
        "倫": "伦",
        "內": "内",
        "連": "连",
        "褲": "裤",
        "護": "护",
        "裝": "装",
        "漁": "渔",
        "鏡": "镜",
        "癡": "痴",
        "強": "强",
        "姦": "奸",
        "隸": "隶",
        "無": "无",
        "貓": "猫",
        "獸": "兽",
        "髮": "发",
        "紋": "纹",
        "環": "环",
        "兒": "儿",
        "宮": "宫",
        "頸": "颈",
        "滲": "渗",
        "攝": "摄",
        "寫": "写",
        "觸": "触",
        "濕": "湿",
        "髒": "脏",
    }
)
TAG_ALIAS_CANONICAL_TEXTS = {
    "綁縛": ("束缚",),
    "绑缚": ("束缚",),
    "束縛": ("束缚",),
    "項圈": ("项圈",),
    "狗鏈": ("项圈",),
    "狗链": ("项圈",),
    "乳頭穿孔": ("乳头穿孔",),
    "乳環": ("乳头穿孔",),
    "乳环": ("乳头穿孔",),
    "阿嘿顏": ("阿黑颜",),
    "阿嘿颜": ("阿黑颜",),
    "阿黑顏": ("阿黑颜",),
    "顏射": ("颜射",),
    "雙馬尾": ("双马尾",),
    "長筒襪": ("长筒袜",),
    "長襪": ("长筒袜",),
    "貧乳": ("贫乳",),
    "破處": ("破处",),
    "蘿莉": ("萝莉",),
    "loli": ("萝莉",),
    "lolicon": ("萝莉",),
    "綠帽癖": ("NTR",),
    "绿帽癖": ("NTR",),
    "寝取られ": ("NTR",),
    "ntr": ("NTR",),
    "乳汁": ("母乳",),
    "內射": ("中出",),
    "内射": ("中出",),
    "中出し": ("中出",),
    "中出汁": ("中出",),
    "亂交": ("乱交",),
    "群交": ("乱交",),
    "乳膠緊身衣": ("乳胶紧身衣",),
    "腹部變形": ("腹部变形",),
    "死庫水": ("死库水",),
    "學校泳衣": ("死库水",),
    "亂倫": ("乱伦",),
    "體格差": ("体格差",),
    "媚藥": ("媚药",),
    "藥物": ("药物",),
    "女兒": ("女儿",),
}
TAG_CATEGORY_SYNONYM_FAMILIES = (
    {
        "canonical": "爆肛",
        "aliases": (
            "肛交",
            "肛门性交",
            "肛門性交",
            "アナル",
            "anal",
            "anal sex",
            "anal intercourse",
        ),
    },
)
TAG_ALLOWED_NON_CJK_DISPLAY_NAMES = {"NTR", "OL", "SM", "3P", "JK", "JC", "JS", "BL", "GL", "TSF", "COSPLAY"}
_PADDLE_OCR_INSTANCE = None
_PADDLE_OCR_UNAVAILABLE = False
_PADDLE_OCR_ERROR = ""
_MANGA_OCR_INSTANCE = None
_MANGA_OCR_UNAVAILABLE = False
_MANGA_OCR_ERROR = ""
_EHTAG_TRANSLATION_CACHE: dict[Path, dict[str, dict[str, str]]] = {}
_EHTAG_REVERSE_TRANSLATION_CACHE: dict[tuple[Path, int], dict[str, list[dict[str, str]]]] = {}


class ArchivePasswordRequiredError(RuntimeError):
    pass


class ArchivePasswordIncorrectError(RuntimeError):
    pass


def natural_key(value: object) -> list[tuple[int, object]]:
    text = str(value).replace("\\", "/").casefold()
    chunks = re.split(r"(\d+)", text)
    key: list[tuple[int, object]] = []
    for chunk in chunks:
        if chunk.isdigit():
            key.append((0, int(chunk)))
        else:
            key.append((1, chunk))
    return key


def is_image(path: str | Path) -> bool:
    return Path(str(path)).suffix.casefold() in IMAGE_EXTS


def is_archive(path: str | Path) -> bool:
    return Path(str(path)).suffix.casefold() in ARCHIVE_EXTS


def normalize_internal_path(path: str) -> str:
    value = path.replace("\\", "/")
    while value.startswith("./"):
        value = value[2:]
    return value.strip("/")


def parent_internal_path(path: str) -> str:
    normalized = normalize_internal_path(path)
    if "/" not in normalized:
        return ""
    return normalized.rsplit("/", 1)[0]


def display_name_from_parts(parts: list[str], fallback: str) -> str:
    cleaned = [part for part in parts if part and part not in (".", "..")]
    if not cleaned:
        return fallback
    return "".join(cleaned)


def display_name_for_folder(source_root: Path, comic_dir: Path) -> str:
    try:
        relative_parts = list(comic_dir.resolve().relative_to(source_root.resolve()).parts)
    except ValueError:
        relative_parts = [comic_dir.name]

    if not relative_parts:
        return comic_dir.name

    return display_name_from_parts(relative_parts, comic_dir.name)


def display_name_for_archive(archive_path: Path, internal_dir: str) -> str:
    if not internal_dir:
        return archive_path.stem

    parts = normalize_internal_path(internal_dir).split("/")
    return display_name_from_parts(parts, archive_path.stem)


def stable_id(unique_key: str) -> str:
    return hashlib.sha256(unique_key.encode("utf-8")).hexdigest()[:24]


def normcase_path(path: Path) -> str:
    return os.path.normcase(str(path.resolve()))


def path_identity(path: str | Path) -> str:
    return os.path.normcase(os.path.abspath(str(path)))


def archive_password_key(path: str | Path) -> str:
    return hashlib.sha256(path_identity(path).encode("utf-8")).hexdigest()


def archive_password_store_path(data_dir: Path) -> Path:
    return data_dir / "archive-passwords.json"


def temp_json_path(path: Path) -> Path:
    return path.with_name(f"{path.name}.{os.getpid()}.{time.monotonic_ns()}.tmp")


def replace_file_with_retry(temp_path: Path, target_path: Path, attempts: int = 40) -> None:
    last_error: OSError | None = None
    for attempt in range(attempts):
        try:
            os.replace(temp_path, target_path)
            return
        except PermissionError as exc:
            last_error = exc
        except OSError as exc:
            if getattr(exc, "winerror", None) != 5:
                raise
            last_error = exc
        time.sleep(min(0.5, 0.05 * (attempt + 1)))
    if last_error is not None:
        raise last_error
    raise RuntimeError(f"无法保存文件：{target_path}")


def load_archive_passwords(data_dir: Path) -> dict[str, str]:
    path = archive_password_store_path(data_dir)
    if not path.exists():
        return {}
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        return {}
    if not isinstance(data, dict):
        return {}
    return {str(key): str(value) for key, value in data.items() if str(key) and str(value)}


def save_archive_password(data_dir: Path, archive_path: Path, password: str) -> None:
    passwords = load_archive_passwords(data_dir)
    passwords[archive_password_key(archive_path)] = password
    path = archive_password_store_path(data_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = temp_json_path(path)
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(passwords, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    replace_file_with_retry(temp_path, path)


def get_archive_password(data_dir: Path, archive_path: Path, password: str | None = None) -> str | None:
    if password is not None:
        return password
    return load_archive_passwords(data_dir).get(archive_password_key(archive_path))


def path_is_relative_to(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def existing_archive_source_name(library: dict, archive_path: Path) -> str | None:
    target = path_identity(archive_path)
    for item in library.get("items", []):
        if not isinstance(item, dict) or item.get("kind") != "archive":
            continue
        source_path = str(item.get("sourcePath", "") or "")
        if not source_path:
            continue
        if path_identity(source_path) == target:
            return str(item.get("name", "") or archive_path.stem)
    return None


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def ensure_library(data_dir: Path) -> dict:
    library_path = data_dir / "library.json"
    if not library_path.exists():
        return {"version": 1, "items": [], "categories": list(DEFAULT_CATEGORIES)}

    with library_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if not isinstance(data, dict):
        return {"version": 1, "items": [], "categories": list(DEFAULT_CATEGORIES)}

    data.setdefault("version", 1)
    data.setdefault("items", [])
    if not isinstance(data["items"], list):
        data["items"] = []
    if "categories" in data:
        data["categories"] = normalize_categories(data.get("categories", []), include_defaults=False)
    else:
        data["categories"] = normalize_categories(DEFAULT_CATEGORIES, include_defaults=False)
    data["categoryRecords"] = normalize_category_records(data.get("categoryRecords", []))
    data["tagTranslations"] = normalize_tag_translations(data.get("tagTranslations", {}))
    data["tagBlacklist"] = normalize_tag_blacklist(data.get("tagBlacklist", []))
    data["categoryAliases"] = normalize_category_aliases(data.get("categoryAliases", []))
    data["tagRawMappings"] = normalize_tag_raw_mappings(data.get("tagRawMappings", []))
    for item in data["items"]:
        if isinstance(item, dict):
            normalize_item_categories_and_title_status(item)
            normalize_item_title_fields(item)
            normalize_item_password_fields(item)
    prune_disallowed_tag_categories(data)
    apply_category_aliases(data)
    apply_tag_synonym_families(data)
    apply_category_aliases(data)
    return data


def normalize_category_name(name: object) -> str:
    value = str(name or "").strip()
    if value == LEGACY_FAVORITE_CATEGORY:
        return FAVORITE_CATEGORY
    return value


def normalize_categories(values: object, *, include_defaults: bool, allow_assignable_system: bool = False) -> list[str]:
    categories: list[str] = []
    seen: set[str] = set()

    source = []
    if include_defaults:
        source.extend(DEFAULT_CATEGORIES)
    if isinstance(values, list):
        source.extend(values)

    for value in source:
        name = normalize_category_name(value)
        if not name:
            continue
        if name in SYSTEM_CATEGORIES and not (allow_assignable_system and name in ASSIGNABLE_SYSTEM_CATEGORIES):
            continue
        key = name.casefold()
        if key in seen:
            continue
        seen.add(key)
        categories.append(name)
    return categories


def normalize_source_tag(value: object) -> str:
    text = str(value or "").strip().casefold()
    text = re.sub(r"\s+", " ", text)
    return text


def normalize_tag_display_name(value: object) -> str:
    text = str(value or "").strip()
    text = re.sub(r"\s+", " ", text)
    return text.strip(" \t\r\n\"'[]()")


def normalize_tag_translations(values: object) -> dict[str, str]:
    translations: dict[str, str] = {}
    if not isinstance(values, dict):
        return translations

    for key, value in values.items():
        source_tag = normalize_source_tag(key)
        display_name = normalize_tag_display_name(value)
        if source_tag and display_name:
            translations[source_tag] = display_name
    return translations


def text_contains_cjk(value: object) -> bool:
    return any("\u4e00" <= char <= "\u9fff" for char in str(value or ""))


def text_contains_japanese(value: object) -> bool:
    return any("\u3040" <= char <= "\u30ff" or "\u31f0" <= char <= "\u31ff" for char in str(value or ""))


def tag_display_name_is_usable(namespace: str, tag: str, display_name: object) -> bool:
    display = normalize_tag_display_name(display_name)
    if not display:
        return False
    if text_contains_cjk(display) or text_contains_japanese(display):
        return True
    if normalize_source_tag(namespace) == "parody":
        return True

    compact = re.sub(r"[^a-z0-9]+", "", display, flags=re.IGNORECASE).upper()
    if compact in TAG_ALLOWED_NON_CJK_DISPLAY_NAMES:
        return True

    return False


def google_translate_text(text: str, source_lang: str = "en", target_lang: str = "zh-CN") -> str:
    params = urllib.parse.urlencode(
        {
            "client": "gtx",
            "sl": source_lang,
            "tl": target_lang,
            "dt": "t",
            "q": text,
        }
    )
    request = urllib.request.Request(
        f"{GOOGLE_TRANSLATE_URL}?{params}",
        headers={"User-Agent": "Mozilla/5.0"},
    )
    with urllib.request.urlopen(request, timeout=TRANSLATE_REQUEST_TIMEOUT_SECONDS) as response:
        payload = json.loads(response.read().decode("utf-8", errors="replace"))

    pieces: list[str] = []
    if isinstance(payload, list) and payload and isinstance(payload[0], list):
        for segment in payload[0]:
            if isinstance(segment, list) and segment:
                pieces.append(str(segment[0] or ""))
    return normalize_tag_display_name("".join(pieces))


def ehtag_translation_paths(data_dir: Path) -> list[Path]:
    return [
        data_dir / "ehtag-translation" / "db.text.json",
        data_dir / "ehtag-translation" / "db.full.json",
        data_dir / "db.text.json",
    ]


def ehtag_translation_status(data_dir: Path) -> dict:
    for path in ehtag_translation_paths(data_dir):
        if path.exists() and path.is_file():
            return {"available": True, "path": str(path)}
    return {
        "available": False,
        "path": str(ehtag_translation_paths(data_dir)[0]),
        "url": EHTAG_TRANSLATION_URL,
    }


def download_ehtag_translation(data_dir: Path) -> dict:
    target_path = ehtag_translation_paths(data_dir)[0]
    target_path.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        EHTAG_TRANSLATION_URL,
        headers={"User-Agent": "mangaga/0.1"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        content = response.read()

    try:
        payload = json.loads(content.decode("utf-8"))
    except Exception as exc:
        raise RuntimeError(f"EhTagTranslation 下载内容不是有效 JSON：{exc}") from exc

    sections = payload.get("data", []) if isinstance(payload, dict) else []
    if not isinstance(sections, list) or not sections:
        raise RuntimeError("EhTagTranslation 下载内容缺少 data 字段。")

    temp_path = temp_json_path(target_path)
    temp_path.write_bytes(content)
    replace_file_with_retry(temp_path, target_path)
    _EHTAG_TRANSLATION_CACHE.pop(target_path.resolve(), None)
    return {
        "available": True,
        "path": str(target_path),
        "url": EHTAG_TRANSLATION_URL,
        "bytes": len(content),
        "sections": len(sections),
    }


def load_ehtag_translation_db(data_dir: Path) -> dict[str, dict[str, str]]:
    global _EHTAG_TRANSLATION_CACHE

    status = ehtag_translation_status(data_dir)
    if not bool(status.get("available", False)):
        return {}

    path = Path(str(status.get("path", ""))).resolve()
    cached = _EHTAG_TRANSLATION_CACHE.get(path)
    if cached is not None:
        return cached

    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    sections = payload.get("data", []) if isinstance(payload, dict) else []
    translations: dict[str, dict[str, str]] = {}
    if isinstance(sections, list):
        for section in sections:
            if not isinstance(section, dict):
                continue
            front_matters = section.get("frontMatters", {})
            namespace = normalize_source_tag(front_matters.get("key", "") if isinstance(front_matters, dict) else "")
            if not namespace:
                continue
            section_data = section.get("data", {})
            if not isinstance(section_data, dict):
                continue
            namespace_translations: dict[str, str] = {}
            for raw_tag, entry in section_data.items():
                tag_key = normalize_source_tag(raw_tag)
                if not tag_key or not isinstance(entry, dict):
                    continue
                display_name = normalize_tag_display_name(entry.get("name", ""))
                if display_name:
                    namespace_translations[tag_key] = display_name
            translations[namespace] = namespace_translations

    _EHTAG_TRANSLATION_CACHE[path] = translations
    return translations


def lookup_ehtag_translation(data_dir: Path, namespace: str, tag: str) -> str | None:
    namespace_key = normalize_source_tag(namespace) or "other"
    tag_key = normalize_source_tag(tag)
    if not tag_key:
        return None

    db = load_ehtag_translation_db(data_dir)
    namespace_data = db.get(namespace_key, {})
    display_name = normalize_tag_display_name(namespace_data.get(tag_key, ""))
    if display_name:
        return display_name
    return None


def translate_tag_display_name(data_dir: Path, library: dict, namespace: str, tag: str) -> str | None:
    namespace_key = normalize_source_tag(namespace) or "other"
    tag_key = normalize_source_tag(tag)
    if not tag_key:
        return None

    translations = normalize_tag_translations(library.get("tagTranslations", {}))
    library["tagTranslations"] = translations
    cache_key = eh_tag_key(namespace_key, tag_key)
    cached = translations.get(cache_key)
    if cached:
        return cached

    translation_mode = normalize_source_tag(os.environ.get("MANGAGA_TAG_TRANSLATION_MODE", "ehtag")) or "ehtag"
    if translation_mode == "none":
        return None

    translated = normalize_tag_display_name(lookup_ehtag_translation(data_dir, namespace_key, tag_key))
    if not translated and translation_mode == "online":
        try:
            translated = normalize_tag_display_name(google_translate_text(tag_key, "en", "zh-CN"))
        except Exception:
            translated = ""

    if not tag_display_name_is_usable(namespace_key, tag_key, translated):
        return None

    translations[cache_key] = translated
    return translated


def split_eh_tag(raw_tag: object) -> tuple[str, str]:
    text = normalize_source_tag(raw_tag)
    if ":" in text:
        namespace, tag = text.split(":", 1)
        return namespace.strip(), tag.strip()
    return "other", text.strip()


def stable_tag_record_id(namespace: str, tag: str) -> str:
    normalized = f"{normalize_source_tag(namespace)}:{normalize_source_tag(tag)}"
    slug = re.sub(r"[^a-z0-9]+", "_", normalized).strip("_")[:60] or "tag"
    digest = hashlib.sha1(normalized.encode("utf-8")).hexdigest()[:10]
    return f"tag:{slug}:{digest}"


def eh_tag_key(namespace: str, tag: str) -> str:
    return f"{normalize_source_tag(namespace) or 'other'}:{normalize_source_tag(tag)}"


def normalize_tag_alias_key(value: object) -> str:
    text = normalize_tag_display_name(value)
    text = unicodedata.normalize("NFKC", text).casefold()
    text = re.sub(r"[\s　_\-:/\\|,，.。;；:：、·・!！?？()\[\]{}【】<>《》\"'“”‘’]+", "", text)
    return text.strip()


def simplify_tag_alias_text(value: object) -> str:
    return normalize_tag_display_name(value).translate(TAG_TRADITIONAL_TO_SIMPLIFIED)


def tag_alias_text_variants(value: object) -> list[str]:
    variants: list[str] = []
    seen_keys: set[str] = set()
    queue = [normalize_tag_display_name(value), simplify_tag_alias_text(value)]

    index = 0
    while index < len(queue):
        text = queue[index]
        index += 1
        key = normalize_tag_alias_key(text)
        if not key or key in seen_keys:
            continue
        seen_keys.add(key)
        variants.append(text)

        simplified_key = normalize_tag_alias_key(simplify_tag_alias_text(text))
        if simplified_key and simplified_key not in seen_keys:
            queue.append(simplify_tag_alias_text(text))

        for alias, replacements in TAG_ALIAS_CANONICAL_TEXTS.items():
            alias_keys = {
                normalize_tag_alias_key(alias),
                normalize_tag_alias_key(simplify_tag_alias_text(alias)),
            }
            if key not in alias_keys and simplified_key not in alias_keys:
                continue
            for replacement in replacements:
                replacement_text = normalize_tag_display_name(replacement)
                replacement_key = normalize_tag_alias_key(replacement_text)
                if replacement_text and replacement_key not in seen_keys:
                    queue.append(replacement_text)

        for family in TAG_CATEGORY_SYNONYM_FAMILIES:
            canonical = normalize_category_name(family.get("canonical", ""))
            aliases = family.get("aliases", ())
            family_texts = [canonical, *aliases]
            family_keys = {
                candidate_key
                for family_text in family_texts
                for candidate_key in (
                    normalize_tag_alias_key(family_text),
                    normalize_tag_alias_key(simplify_tag_alias_text(family_text)),
                )
                if candidate_key
            }
            if key not in family_keys and simplified_key not in family_keys:
                continue
            for replacement in family_texts:
                replacement_text = normalize_tag_display_name(replacement)
                replacement_key = normalize_tag_alias_key(replacement_text)
                if replacement_text and replacement_key not in seen_keys:
                    queue.append(replacement_text)

    return variants


def tag_alias_search_keys(value: object) -> set[str]:
    return {key for text in tag_alias_text_variants(value) for key in {normalize_tag_alias_key(text)} if key}


def canonical_tag_category_name(value: object) -> str:
    name = normalize_category_name(value)
    if not name:
        return ""

    keys = tag_alias_search_keys(name)
    if not keys:
        return name

    for family in TAG_CATEGORY_SYNONYM_FAMILIES:
        canonical = normalize_category_name(family.get("canonical", ""))
        if not canonical:
            continue
        family_texts = [canonical, *family.get("aliases", ())]
        family_keys = {
            candidate_key
            for family_text in family_texts
            for candidate_key in (
                normalize_tag_alias_key(family_text),
                normalize_tag_alias_key(simplify_tag_alias_text(family_text)),
            )
            if candidate_key
        }
        if keys & family_keys:
            return canonical

    return name


def resolve_tag_category_name(library: dict, value: object) -> str:
    current = normalize_category_name(value)
    seen: set[str] = set()
    while current and current.casefold() not in seen:
        seen.add(current.casefold())
        aliased = resolve_category_alias_target(library, current)
        canonical = canonical_tag_category_name(aliased)
        resolved = resolve_category_alias_target(library, canonical)
        if not resolved or resolved.casefold() == current.casefold():
            return resolved
        current = resolved
    return current


def add_ehtag_reverse_candidate(index: dict[str, list[dict[str, str]]], alias: object, namespace: str, tag: str) -> None:
    namespace_key = normalize_source_tag(namespace) or "other"
    tag_key = normalize_source_tag(tag)
    alias_keys = tag_alias_search_keys(alias)
    if namespace_key not in TAG_TARGET_NAMESPACES or not tag_key or not alias_keys:
        return

    for alias_key in alias_keys:
        bucket = index.setdefault(alias_key, [])
        if not any(candidate.get("namespace") == namespace_key and candidate.get("tag") == tag_key for candidate in bucket):
            bucket.append({"namespace": namespace_key, "tag": tag_key})


def load_ehtag_reverse_translation_index(data_dir: Path) -> dict[str, list[dict[str, str]]]:
    global _EHTAG_REVERSE_TRANSLATION_CACHE

    status = ehtag_translation_status(data_dir)
    if not bool(status.get("available", False)):
        return {}

    path = Path(str(status.get("path", ""))).resolve()
    try:
        cache_key = (path, path.stat().st_mtime_ns)
    except OSError:
        return {}

    cached = _EHTAG_REVERSE_TRANSLATION_CACHE.get(cache_key)
    if cached is not None:
        return cached

    db = load_ehtag_translation_db(data_dir)
    index: dict[str, list[dict[str, str]]] = {}
    for namespace in TAG_TARGET_NAMESPACES:
        for tag_key, display_name in db.get(namespace, {}).items():
            add_ehtag_reverse_candidate(index, display_name, namespace, tag_key)
            add_ehtag_reverse_candidate(index, tag_key, namespace, tag_key)

    _EHTAG_REVERSE_TRANSLATION_CACHE = {
        key: value
        for key, value in _EHTAG_REVERSE_TRANSLATION_CACHE.items()
        if key[0] != path
    }
    _EHTAG_REVERSE_TRANSLATION_CACHE[cache_key] = index
    return index


def build_library_ehtag_reverse_translation_index(library: dict) -> dict[str, list[dict[str, str]]]:
    translations = normalize_tag_translations(library.get("tagTranslations", {}))
    library["tagTranslations"] = translations
    index: dict[str, list[dict[str, str]]] = {}
    for source_key, display_name in translations.items():
        namespace, tag = split_eh_tag(source_key)
        add_ehtag_reverse_candidate(index, display_name, namespace, tag)
        add_ehtag_reverse_candidate(index, tag, namespace, tag)
    return index


def choose_ehtag_reverse_candidate(candidates: list[dict[str, str]]) -> dict[str, str] | None:
    if not candidates:
        return None

    unique: dict[tuple[str, str], dict[str, str]] = {}
    for candidate in candidates:
        namespace = normalize_source_tag(candidate.get("namespace", "")) or "other"
        tag = normalize_source_tag(candidate.get("tag", ""))
        if namespace in TAG_TARGET_NAMESPACES and tag:
            unique[(namespace, tag)] = {"namespace": namespace, "tag": tag}
    if not unique:
        return None

    priority = {namespace: index for index, namespace in enumerate(TAG_NAMESPACE_PRIORITY)}
    return sorted(unique.values(), key=lambda value: (priority.get(value["namespace"], 99), value["tag"]))[0]


def resolve_wnacg_tag_to_eh_tag(
    data_dir: Path,
    library: dict,
    raw_tag: object,
    library_reverse_index: dict[str, list[dict[str, str]]] | None = None,
    db_reverse_index: dict[str, list[dict[str, str]]] | None = None,
) -> dict[str, str] | None:
    tag = normalize_wnacg_tag(raw_tag)
    if not tag:
        return None

    alias_keys = tag_alias_search_keys(tag)
    candidates: list[dict[str, str]] = []
    if alias_keys:
        if library_reverse_index is None:
            library_reverse_index = build_library_ehtag_reverse_translation_index(library)
        if db_reverse_index is None:
            db_reverse_index = load_ehtag_reverse_translation_index(data_dir)
        for alias_key in alias_keys:
            candidates.extend(library_reverse_index.get(alias_key, []))
            candidates.extend(db_reverse_index.get(alias_key, []))

    namespace, direct_tag = split_eh_tag(tag)
    if namespace in TAG_TARGET_NAMESPACES and direct_tag:
        candidates.append({"namespace": namespace, "tag": direct_tag})

    source_key = normalize_source_tag(tag)
    for alias, canonical_tag in KNOWN_PARODY_SEEDS.items():
        if tag_alias_search_keys(alias).intersection(alias_keys) or normalize_source_tag(canonical_tag) == source_key:
            candidates.append({"namespace": "parody", "tag": canonical_tag})

    return choose_ehtag_reverse_candidate(candidates)


def normalize_tag_blacklist(values: object) -> list[str]:
    keys: list[str] = []
    seen: set[str] = set()
    if isinstance(values, list):
        source = values
    elif isinstance(values, set):
        source = list(values)
    else:
        source = []

    for value in source:
        key = normalize_source_tag(value)
        if not key:
            continue
        if ":" not in key:
            key = f"other:{key}"
        if key in seen:
            continue
        seen.add(key)
        keys.append(key)
    return keys


def source_raw_tag_key(source: str, raw_tag: object) -> str:
    return eh_tag_key(source or "other", normalize_source_tag(raw_tag))


def normalize_tag_raw_mapping(mapping: object) -> dict | None:
    if not isinstance(mapping, dict):
        return None

    source = normalize_source_tag(mapping.get("source", "wnacg")) or "wnacg"
    raw_tag = normalize_tag_display_name(mapping.get("rawTag", ""))
    source_tag = normalize_source_tag(mapping.get("sourceTag", raw_tag))
    if not raw_tag or not source_tag:
        return None

    target_kind = normalize_source_tag(mapping.get("targetKind", "eh")) or "eh"
    normalized = {
        "source": source,
        "rawTag": raw_tag,
        "sourceTag": source_tag,
        "targetKind": target_kind,
    }

    if target_kind == "category":
        target_category = normalize_category_name(mapping.get("targetCategory", ""))
        if not target_category:
            return None
        normalized["targetCategory"] = target_category
        return normalized

    namespace = normalize_source_tag(mapping.get("targetNamespace", "")) or normalize_source_tag(mapping.get("namespace", "")) or "other"
    tag = normalize_source_tag(mapping.get("targetTag", "")) or normalize_source_tag(mapping.get("tag", ""))
    if namespace not in TAG_TARGET_NAMESPACES or not tag:
        return None
    normalized["targetKind"] = "eh"
    normalized["targetNamespace"] = namespace
    normalized["targetTag"] = tag
    return normalized


def normalize_tag_raw_mappings(values: object) -> list[dict]:
    mappings: list[dict] = []
    seen: set[tuple[str, str]] = set()
    if not isinstance(values, list):
        return mappings

    for value in values:
        mapping = normalize_tag_raw_mapping(value)
        if mapping is None:
            continue
        key = (mapping["source"], mapping["sourceTag"])
        if key in seen:
            continue
        seen.add(key)
        mappings.append(mapping)
    return mappings


def find_raw_tag_mapping(library: dict, source: str, raw_tag: object) -> dict | None:
    source_key = normalize_source_tag(source) or "wnacg"
    tag_key = normalize_source_tag(raw_tag)
    if not tag_key:
        return None
    for mapping in normalize_tag_raw_mappings(library.get("tagRawMappings", [])):
        if mapping.get("source") == source_key and mapping.get("sourceTag") == tag_key:
            return mapping
    return None


def upsert_raw_tag_mapping(library: dict, mapping: dict) -> dict | None:
    normalized = normalize_tag_raw_mapping(mapping)
    if normalized is None:
        return None

    mappings = normalize_tag_raw_mappings(library.get("tagRawMappings", []))
    key = (normalized["source"], normalized["sourceTag"])
    mappings = [value for value in mappings if (value.get("source"), value.get("sourceTag")) != key]
    mappings.append(normalized)
    library["tagRawMappings"] = mappings
    return normalized


def remove_raw_tag_mapping(library: dict, source: str, raw_tag: object) -> dict | None:
    source_key = normalize_source_tag(source) or "wnacg"
    tag_key = normalize_source_tag(raw_tag)
    mappings = normalize_tag_raw_mappings(library.get("tagRawMappings", []))
    removed: dict | None = None
    kept: list[dict] = []
    for mapping in mappings:
        if mapping.get("source") == source_key and mapping.get("sourceTag") == tag_key:
            removed = mapping
            continue
        kept.append(mapping)
    library["tagRawMappings"] = kept
    return removed


def is_raw_source_tag_blacklisted(library: dict, source: str, raw_tag: object) -> bool:
    key = source_raw_tag_key(source, raw_tag)
    return key in effective_tag_blacklist(library)


def remove_raw_source_tag_from_blacklist(library: dict, source: str, raw_tag: object) -> None:
    key = source_raw_tag_key(source, raw_tag)
    library["tagBlacklist"] = [value for value in normalize_tag_blacklist(library.get("tagBlacklist", [])) if value != key]


def add_raw_source_tag_to_blacklist(library: dict, source: str, raw_tag: object) -> str:
    key = source_raw_tag_key(source, raw_tag)
    blacklist = normalize_tag_blacklist(library.get("tagBlacklist", []))
    if key not in blacklist:
        blacklist.append(key)
    library["tagBlacklist"] = blacklist
    return key


def normalize_category_alias(alias: object) -> dict | None:
    if not isinstance(alias, dict):
        return None

    source_name = normalize_category_name(alias.get("sourceName", ""))
    target_name = normalize_category_name(alias.get("targetName", ""))
    if not source_name or not target_name:
        return None
    if source_name in SYSTEM_CATEGORIES or target_name in SYSTEM_CATEGORIES:
        return None
    if source_name.casefold() == target_name.casefold():
        return None

    normalized = {
        "sourceName": source_name,
        "targetName": target_name,
        "sourceKind": str(alias.get("sourceKind", MANUAL_CATEGORY_KIND) or MANUAL_CATEGORY_KIND),
    }
    source_tag = normalize_source_tag(alias.get("sourceTag", ""))
    if source_tag:
        normalized["sourceKind"] = TAG_KIND
        normalized["sourceNamespace"] = normalize_source_tag(alias.get("sourceNamespace", "other")) or "other"
        normalized["sourceTag"] = source_tag
    return normalized


def normalize_category_aliases(values: object) -> list[dict]:
    aliases: list[dict] = []
    seen: set[tuple[str, str, str]] = set()
    if not isinstance(values, list):
        return aliases

    for value in values:
        alias = normalize_category_alias(value)
        if alias is None:
            continue
        if alias.get("sourceKind") == TAG_KIND:
            key = (TAG_KIND, str(alias.get("sourceNamespace", "other")), str(alias.get("sourceTag", "")))
        else:
            key = (MANUAL_CATEGORY_KIND, alias["sourceName"].casefold(), "")
        if key in seen:
            continue
        seen.add(key)
        aliases.append(alias)
    return aliases


def find_category_alias_by_name(library: dict, name: str) -> dict | None:
    key = normalize_category_name(name).casefold()
    if not key:
        return None
    for alias in normalize_category_aliases(library.get("categoryAliases", [])):
        if alias["sourceName"].casefold() == key:
            return alias
    return None


def find_category_alias_by_tag(library: dict, namespace: str, tag: str) -> dict | None:
    namespace_key = normalize_source_tag(namespace) or "other"
    tag_key = normalize_source_tag(tag)
    if not tag_key:
        return None
    for alias in normalize_category_aliases(library.get("categoryAliases", [])):
        if alias.get("sourceKind") != TAG_KIND:
            continue
        if alias.get("sourceNamespace") == namespace_key and alias.get("sourceTag") == tag_key:
            return alias
    return None


def resolve_category_alias_target(library: dict, name: str) -> str:
    current = normalize_category_name(name)
    seen: set[str] = set()
    while current and current.casefold() not in seen:
        seen.add(current.casefold())
        alias = find_category_alias_by_name(library, current)
        if alias is None:
            break
        current = normalize_category_name(alias.get("targetName", current))
    return current


def add_category_alias(library: dict, alias: dict) -> None:
    normalized_alias = normalize_category_alias(alias)
    if normalized_alias is None:
        return
    aliases = normalize_category_aliases(library.get("categoryAliases", []))
    if normalized_alias.get("sourceKind") == TAG_KIND:
        source_key = (TAG_KIND, str(normalized_alias.get("sourceNamespace", "other")), str(normalized_alias.get("sourceTag", "")))
        aliases = [
            value
            for value in aliases
            if (value.get("sourceKind"), str(value.get("sourceNamespace", "other")), str(value.get("sourceTag", ""))) != source_key
        ]
    else:
        source_key = normalized_alias["sourceName"].casefold()
        aliases = [value for value in aliases if value["sourceName"].casefold() != source_key]
    aliases.append(normalized_alias)
    library["categoryAliases"] = aliases


def effective_tag_blacklist(library: dict | None = None) -> set[str]:
    keys = set(EH_TAG_BLACKLIST)
    if isinstance(library, dict):
        keys.update(normalize_tag_blacklist(library.get("tagBlacklist", [])))
    return keys


def is_eh_tag_blacklisted(namespace: str, tag: str, library: dict | None = None) -> bool:
    return eh_tag_key(namespace, tag) in effective_tag_blacklist(library)


def should_create_eh_tag_category(namespace: str, tag: str, library: dict | None = None) -> bool:
    namespace_key = normalize_source_tag(namespace) or "other"
    if namespace_key not in TAG_TARGET_NAMESPACES:
        return False
    if not normalize_source_tag(tag):
        return False
    if is_eh_tag_blacklisted(namespace, tag, library):
        return False
    return True


def should_create_direct_tag_category(namespace: str, tag: str, library: dict | None = None) -> bool:
    namespace_key = normalize_source_tag(namespace) or "other"
    tag_key = normalize_source_tag(tag)
    if not tag_key:
        return False
    if is_eh_tag_blacklisted(namespace_key, tag_key, library):
        return False
    return True


def normalize_category_record(record: object) -> dict | None:
    if not isinstance(record, dict):
        return None

    record_id = str(record.get("id", "") or "").strip()
    name = normalize_category_name(record.get("name", ""))
    kind = str(record.get("kind", MANUAL_CATEGORY_KIND) or MANUAL_CATEGORY_KIND).strip() or MANUAL_CATEGORY_KIND
    if not record_id or not name:
        return None

    normalized = {
        "id": record_id,
        "name": name,
        "kind": kind,
    }
    if kind == TAG_KIND:
        namespace = normalize_source_tag(record.get("sourceNamespace", "other")) or "other"
        source_tag = normalize_source_tag(record.get("sourceTag", ""))
        if not source_tag:
            return None
        normalized.update(
            {
                "source": str(record.get("source", "exhentai") or "exhentai"),
                "sourceNamespace": namespace,
                "sourceTag": source_tag,
                "editableName": bool(record.get("editableName", True)),
            }
        )
    return normalized


def normalize_category_records(values: object) -> list[dict]:
    records: list[dict] = []
    seen_ids: set[str] = set()
    if not isinstance(values, list):
        return records

    for value in values:
        record = normalize_category_record(value)
        if record is None:
            continue
        record_id = record["id"]
        if record_id in seen_ids:
            continue
        seen_ids.add(record_id)
        records.append(record)
    return records


def category_name_exists(library: dict, name: str) -> bool:
    key = normalize_category_name(name).casefold()
    return any(str(category).casefold() == key for category in normalize_categories(library.get("categories", []), include_defaults=False))


def unique_category_name(library: dict, desired_name: str) -> str:
    base = normalize_category_name(desired_name) or "Tag"
    if not category_name_exists(library, base):
        return base

    index = 2
    while True:
        candidate = f"{base} {index}"
        if not category_name_exists(library, candidate):
            return candidate
        index += 1


def find_tag_category_record(library: dict, namespace: str, tag: str) -> dict | None:
    namespace_key = normalize_source_tag(namespace)
    tag_key = normalize_source_tag(tag)
    for record in normalize_category_records(library.get("categoryRecords", [])):
        if record.get("kind") != TAG_KIND:
            continue
        if record.get("sourceNamespace") == namespace_key and record.get("sourceTag") == tag_key:
            return record
    return None


def rename_category_references(library: dict, old_name: str, new_name: str) -> None:
    old_key = normalize_category_name(old_name).casefold()
    if not old_key or old_key == normalize_category_name(new_name).casefold():
        return

    categories = normalize_categories(library.get("categories", []), include_defaults=False)
    renamed_categories: list[str] = []
    seen_categories: set[str] = set()
    for value in categories:
        renamed = new_name if value.casefold() == old_key else value
        renamed_key = renamed.casefold()
        if renamed_key in seen_categories:
            continue
        seen_categories.add(renamed_key)
        renamed_categories.append(renamed)
    library["categories"] = renamed_categories

    for item in library.get("items", []):
        if not isinstance(item, dict):
            continue
        item_categories = normalize_categories(
            item.get("categories", []),
            include_defaults=False,
            allow_assignable_system=True,
        )
        item_categories = [value for value in item_categories if value not in MANAGED_TITLE_CATEGORIES]
        renamed_item_categories: list[str] = []
        seen_item_categories: set[str] = set()
        for value in item_categories:
            renamed = new_name if value.casefold() == old_key else value
            renamed_key = renamed.casefold()
            if renamed_key in seen_item_categories:
                continue
            seen_item_categories.add(renamed_key)
            renamed_item_categories.append(renamed)
        item["categories"] = renamed_item_categories

        raw_category_record = item.get("rawTagCategories")
        if not isinstance(raw_category_record, dict):
            continue
        for source_record in raw_category_record.values():
            if not isinstance(source_record, dict):
                continue
            for raw_tag, values in list(source_record.items()):
                source_values = values if isinstance(values, list) else [values]
                renamed_values: list[str] = []
                seen_values: set[str] = set()
                for value in source_values:
                    category_name = normalize_category_name(value)
                    if not category_name:
                        continue
                    renamed = new_name if category_name.casefold() == old_key else category_name
                    renamed_key = renamed.casefold()
                    if renamed_key in seen_values:
                        continue
                    seen_values.add(renamed_key)
                    renamed_values.append(renamed)
                if renamed_values:
                    source_record[raw_tag] = renamed_values
                else:
                    source_record.pop(raw_tag, None)


def apply_category_aliases(library: dict) -> None:
    aliases = normalize_category_aliases(library.get("categoryAliases", []))
    library["categoryAliases"] = aliases
    if not aliases:
        return

    for alias in aliases:
        alias["targetName"] = resolve_category_alias_target(library, alias["targetName"])

    source_name_keys = {alias["sourceName"].casefold() for alias in aliases}

    categories = normalize_categories(library.get("categories", []), include_defaults=False)
    normalized_categories: list[str] = []
    seen_categories: set[str] = set()
    for category in categories:
        target = resolve_category_alias_target(library, category)
        if category.casefold() in source_name_keys:
            category = target
        else:
            category = target
        if not category or category in SYSTEM_CATEGORIES:
            continue
        key = category.casefold()
        if key in seen_categories:
            continue
        seen_categories.add(key)
        normalized_categories.append(category)
    library["categories"] = normalized_categories

    for item in library.get("items", []):
        if not isinstance(item, dict):
            continue
        item_categories = normalize_categories(
            item.get("categories", []),
            include_defaults=False,
            allow_assignable_system=True,
        )
        item_categories = [value for value in item_categories if value not in MANAGED_TITLE_CATEGORIES]
        normalized_item_categories: list[str] = []
        seen_item_categories: set[str] = set()
        for category in item_categories:
            if category in ASSIGNABLE_SYSTEM_CATEGORIES:
                target = category
            else:
                target = resolve_category_alias_target(library, category)
            if not target:
                continue
            key = target.casefold()
            if key in seen_item_categories:
                continue
            seen_item_categories.add(key)
            normalized_item_categories.append(target)
        item["categories"] = normalized_item_categories

    tag_alias_keys = {
        eh_tag_key(str(alias.get("sourceNamespace", "other")), str(alias.get("sourceTag", "")))
        for alias in aliases
        if alias.get("sourceKind") == TAG_KIND and alias.get("sourceTag")
    }
    records = normalize_category_records(library.get("categoryRecords", []))
    kept_records: list[dict] = []
    for record in records:
        record_name_key = str(record.get("name", "")).casefold()
        record_tag_key = eh_tag_key(str(record.get("sourceNamespace", "other")), str(record.get("sourceTag", "")))
        if record_name_key in source_name_keys or record_tag_key in tag_alias_keys:
            continue
        kept_records.append(record)
    library["categoryRecords"] = kept_records


def apply_tag_synonym_families(library: dict) -> None:
    records = normalize_category_records(library.get("categoryRecords", []))
    library["categoryRecords"] = records

    rename_pairs: list[tuple[str, str]] = []
    for record in records:
        if record.get("kind") != TAG_KIND:
            continue
        old_name = normalize_category_name(record.get("name", ""))
        new_name = resolve_tag_category_name(library, old_name)
        if not old_name or not new_name or old_name.casefold() == new_name.casefold():
            continue
        record["name"] = new_name
        rename_pairs.append((old_name, new_name))

    mappings = normalize_tag_raw_mappings(library.get("tagRawMappings", []))
    for mapping in mappings:
        if mapping.get("targetKind") != "category":
            continue
        old_name = normalize_category_name(mapping.get("targetCategory", ""))
        new_name = resolve_tag_category_name(library, old_name)
        if not old_name or not new_name or old_name.casefold() == new_name.casefold():
            continue
        mapping["targetCategory"] = new_name
        rename_pairs.append((old_name, new_name))
    library["tagRawMappings"] = mappings

    for old_name, new_name in rename_pairs:
        rename_category_references(library, old_name, new_name)


def prune_disallowed_tag_categories(library: dict) -> None:
    records = normalize_category_records(library.get("categoryRecords", []))
    aliases = normalize_category_aliases(library.get("categoryAliases", []))
    disallowed_tag_keys = effective_tag_blacklist(library)
    kept_records: list[dict] = []
    removed_names: set[str] = set()

    for record in records:
        if record.get("kind") != TAG_KIND:
            kept_records.append(record)
            continue

        source = str(record.get("source", "exhentai") or "exhentai").casefold()
        namespace = str(record.get("sourceNamespace", "other"))
        source_tag = str(record.get("sourceTag", ""))
        if source == "exhentai" and not should_create_eh_tag_category(namespace, source_tag, library):
            removed_names.add(str(record.get("name", "")))
            continue
        if source != "exhentai" and not should_create_direct_tag_category(namespace, source_tag, library):
            removed_names.add(str(record.get("name", "")))
            continue

        kept_records.append(record)

    kept_aliases: list[dict] = []
    for alias in aliases:
        if alias.get("sourceKind") != TAG_KIND:
            kept_aliases.append(alias)
            continue

        namespace = str(alias.get("sourceNamespace", "other") or "other")
        source_tag = str(alias.get("sourceTag", "") or "")
        tag_key = eh_tag_key(namespace, source_tag)
        if tag_key in disallowed_tag_keys:
            removed_names.add(str(alias.get("sourceName", "")))
            target_name = resolve_category_alias_target(library, str(alias.get("targetName", "")))
            removed_names.add(target_name or str(alias.get("targetName", "")))
            continue

        kept_aliases.append(alias)

    if removed_names:
        removed_keys = {name.casefold() for name in removed_names if name}
        categories = normalize_categories(library.get("categories", []), include_defaults=False)
        library["categories"] = [category for category in categories if category.casefold() not in removed_keys]
        for item in library.get("items", []):
            if not isinstance(item, dict):
                continue
            item_categories = normalize_categories(
                item.get("categories", []),
                include_defaults=False,
                allow_assignable_system=True,
            )
            item["categories"] = [category for category in item_categories if category.casefold() not in removed_keys and category not in MANAGED_TITLE_CATEGORIES]
        kept_aliases = [
            alias
            for alias in kept_aliases
            if alias["sourceName"].casefold() not in removed_keys
            and str(alias.get("targetName", "")).casefold() not in removed_keys
        ]

    library["categoryRecords"] = kept_records
    library["categoryAliases"] = kept_aliases


def ensure_tag_category(data_dir: Path, library: dict, namespace: str, tag: str) -> str | None:
    namespace_key = normalize_source_tag(namespace) or "other"
    tag_key = normalize_source_tag(tag)
    if not tag_key:
        raise RuntimeError("Tag 为空，无法创建分类。")
    if not should_create_eh_tag_category(namespace_key, tag_key, library):
        return None

    alias = find_category_alias_by_tag(library, namespace_key, tag_key)
    if alias is not None:
        target_name = resolve_tag_category_name(library, str(alias.get("targetName", "")))
        if target_name:
            return ensure_raw_category_exists(library, target_name)

    records = normalize_category_records(library.get("categoryRecords", []))
    library["categoryRecords"] = records

    record = next(
        (
            value
            for value in records
            if value.get("kind") == TAG_KIND
            and value.get("sourceNamespace") == namespace_key
            and value.get("sourceTag") == tag_key
        ),
        None,
    )
    if record is not None:
        old_name = normalize_category_name(record["name"])
        name = resolve_tag_category_name(library, old_name)
        if name and old_name.casefold() != name.casefold():
            record["name"] = name
            rename_category_references(library, old_name, name)
        if not name:
            return None
        if not category_name_exists(library, name):
            categories = normalize_categories(library.get("categories", []), include_defaults=False)
            categories.append(name)
            library["categories"] = categories
        return name

    desired_display_name = translate_tag_display_name(data_dir, library, namespace_key, tag_key)
    if desired_display_name is None:
        return None
    display_name = resolve_tag_category_name(library, desired_display_name)
    if not display_name:
        return None
    record = {
        "id": stable_tag_record_id(namespace_key, tag_key),
        "name": display_name,
        "kind": TAG_KIND,
        "source": "exhentai",
        "sourceNamespace": namespace_key,
        "sourceTag": tag_key,
        "editableName": True,
    }
    records.append(record)
    library["categoryRecords"] = records

    ensure_raw_category_exists(library, display_name)
    return display_name


def ensure_direct_tag_category(library: dict, display_name: str, source: str, namespace: str, tag: str) -> str | None:
    namespace_key = normalize_source_tag(namespace) or "other"
    tag_key = normalize_source_tag(tag)
    if not should_create_direct_tag_category(namespace_key, tag_key, library):
        return None

    alias = find_category_alias_by_tag(library, namespace_key, tag_key)
    if alias is not None:
        target_name = resolve_tag_category_name(library, str(alias.get("targetName", "")))
        if target_name:
            return ensure_raw_category_exists(library, target_name)

    records = normalize_category_records(library.get("categoryRecords", []))
    library["categoryRecords"] = records

    record = next(
        (
            value
            for value in records
            if value.get("kind") == TAG_KIND
            and value.get("sourceNamespace") == namespace_key
            and value.get("sourceTag") == tag_key
        ),
        None,
    )
    if record is not None:
        old_name = normalize_category_name(record["name"])
        name = resolve_tag_category_name(library, old_name)
        if name and old_name.casefold() != name.casefold():
            record["name"] = name
            rename_category_references(library, old_name, name)
        if not name:
            return None
        if not category_name_exists(library, name):
            categories = normalize_categories(library.get("categories", []), include_defaults=False)
            categories.append(name)
            library["categories"] = categories
        return name

    normalized_display_name = resolve_tag_category_name(library, display_name)
    if not normalized_display_name:
        return None
    record = {
        "id": stable_tag_record_id(namespace_key, tag_key),
        "name": normalized_display_name,
        "kind": TAG_KIND,
        "source": source,
        "sourceNamespace": namespace_key,
        "sourceTag": tag_key,
        "editableName": True,
    }
    records.append(record)
    library["categoryRecords"] = records

    ensure_raw_category_exists(library, normalized_display_name)
    return normalized_display_name


def normalize_title_status(value: object) -> str:
    status = str(value or "").strip().casefold()
    if status in {TITLE_STATUS_RECOGNIZING, TITLE_STATUS_PENDING}:
        return status
    return TITLE_STATUS_NONE


def normalize_tag_status(value: object) -> str:
    status = str(value or "").strip().casefold()
    if status == TAG_STATUS_NOT_FOUND:
        return TAG_STATUS_NOT_FOUND
    return TAG_STATUS_NONE


def get_title_status(item: dict) -> str:
    return normalize_title_status(item.get("titleStatus", ""))


def get_tag_status(item: dict) -> str:
    return normalize_tag_status(item.get("tagStatus", ""))


def set_title_status(item: dict, status: str) -> None:
    normalized = normalize_title_status(status)
    if normalized:
        item["titleStatus"] = normalized
    else:
        item.pop("titleStatus", None)


def set_tag_status(item: dict, status: str) -> None:
    normalized = normalize_tag_status(status)
    if normalized:
        item["tagStatus"] = normalized
    else:
        item.pop("tagStatus", None)


def normalize_item_categories_and_title_status(item: dict) -> None:
    item_categories = normalize_categories(
        item.get("categories", []),
        include_defaults=False,
        allow_assignable_system=True,
    )
    status = get_title_status(item)

    if PENDING_TITLE_CATEGORY in item_categories:
        status = TITLE_STATUS_PENDING
    elif TITLE_RECOGNIZING_CATEGORY in item_categories:
        status = TITLE_STATUS_RECOGNIZING

    item["categories"] = [category for category in item_categories if category not in MANAGED_TITLE_CATEGORIES]
    set_title_status(item, status)
    set_tag_status(item, get_tag_status(item))


def normalize_title_key(value: str) -> str:
    return re.sub(r"\s+", "", value).casefold()


def normalize_title_candidate_name(value: object) -> str:
    text = str(value or "").strip()
    text = re.sub(r"\s+", " ", text)
    return text.strip(" \t\r\n\"'`.,;:!?，。！？、·・|/\\[]{}【】()（）")


def contains_cjk_or_kana(text: str) -> bool:
    return any("\u3040" <= char <= "\u30ff" or "\u3400" <= char <= "\u9fff" for char in text)


def looks_like_mojibake(text: str) -> bool:
    if "\ufffd" in text:
        return True
    if re.search(r"(Ã|Â|â|æ|è|é|å|ç|ð|ã|¤|¥|¢|½|¼|¾|ƒ|œ|�)", text):
        return True
    if re.search(r"\\x[0-9a-fA-F]{2}|%[0-9a-fA-F]{2}", text):
        return True

    question_count = text.count("?") + text.count("？")
    if question_count >= 2:
        return True

    return False


def looks_like_number_only_name(text: str) -> bool:
    compact = re.sub(r"[\s._\-()\[\]【】（）]+", "", text).casefold()
    if not compact:
        return True
    if re.fullmatch(r"\d{1,5}", compact):
        return True
    if re.fullmatch(r"(第)?\d{1,5}(话|話|回|集|卷|巻)", compact):
        return True
    if re.fullmatch(r"(ch|chapter|chap|ep|episode|vol|volume)\d{1,5}", compact):
        return True
    return False


def looks_like_hash_name(text: str) -> bool:
    compact = re.sub(r"[\s._\-()\[\]【】（）]+", "", text).casefold()
    if re.fullmatch(r"[0-9a-f]{16,64}", compact):
        return True
    return False


def name_needs_title_recognition(name: object) -> bool:
    text = str(name or "").strip()
    if not text:
        return True

    generic_names = {
        "新建文件夹",
        "新建文件夹2",
        "untitled",
        "unknown",
        "no title",
        "noname",
        "no_name",
    }
    if text.casefold() in generic_names:
        return True
    if looks_like_number_only_name(text):
        return True
    if looks_like_hash_name(text):
        return True
    if looks_like_mojibake(text):
        return True

    return False


def normalize_title_candidates(values: object) -> list[dict]:
    candidates: list[dict] = []
    seen: set[str] = set()

    if not isinstance(values, list):
        return candidates

    for value in values:
        if isinstance(value, dict):
            name = normalize_title_candidate_name(value.get("name", ""))
            page_index = value.get("pageIndex")
            page_label = str(value.get("pageLabel", "") or "").strip()
            score = value.get("score")
        else:
            name = normalize_title_candidate_name(value)
            page_index = None
            page_label = ""
            score = None

        if not name:
            continue

        key = normalize_title_key(name)
        if key in seen:
            continue
        seen.add(key)

        candidate = {"name": name}
        if isinstance(page_index, int):
            candidate["pageIndex"] = page_index
            candidate["pageLabel"] = page_label or f"第{page_index + 1}页"
        elif page_label:
            candidate["pageLabel"] = page_label
        if isinstance(score, (int, float)):
            candidate["score"] = round(float(score), 2)
        candidates.append(candidate)

        if len(candidates) >= TITLE_CANDIDATE_LIMIT:
            break

    return candidates


def normalize_item_title_fields(item: dict) -> None:
    candidates = normalize_title_candidates(item.get("titleCandidates", []))
    item["titleCandidates"] = candidates
    item["titleSelected"] = bool(item.get("titleSelected", False)) if candidates else False
    if not candidates:
        item.pop("titleOriginalName", None)
        item.pop("titleDetectedAt", None)
        item.pop("titleSelectedAt", None)


def normalize_item_password_fields(item: dict) -> None:
    if bool(item.get("requiresPassword", False)):
        item["requiresPassword"] = True
    else:
        item.pop("requiresPassword", None)


def ensure_raw_category_exists(library: dict, category: str) -> str:
    name = normalize_category_name(category)
    if not name:
        raise RuntimeError("分类名称不能为空。")
    if name in SYSTEM_CATEGORIES:
        raise RuntimeError("系统分类不能作为自定义分类。")

    existing = normalize_categories(library.get("categories", []), include_defaults=False)
    for value in existing:
        if value.casefold() == name.casefold():
            library["categories"] = existing
            return value

    existing.append(name)
    library["categories"] = existing
    return name


def ensure_category_exists(library: dict, category: str) -> str:
    name = normalize_category_name(category)
    if not name:
        raise RuntimeError("分类名称不能为空。")
    name = resolve_category_alias_target(library, name)
    return ensure_raw_category_exists(library, name)


def ensure_assignable_category_exists(library: dict, category: str) -> str:
    name = normalize_category_name(category)
    if not name:
        raise RuntimeError("分类名称不能为空。")
    if name in ASSIGNABLE_SYSTEM_CATEGORIES:
        return name
    name = resolve_category_alias_target(library, name)
    return ensure_category_exists(library, name)


def add_category_to_item(item: dict, category: str) -> None:
    name = normalize_category_name(category)
    if not name:
        return

    if name in TITLE_STATUS_BY_CATEGORY:
        set_title_status(item, TITLE_STATUS_BY_CATEGORY[name])
        return

    item_categories = normalize_categories(
        item.get("categories", []),
        include_defaults=False,
        allow_assignable_system=True,
    )
    item_categories = [value for value in item_categories if value not in MANAGED_TITLE_CATEGORIES]
    if not any(value.casefold() == name.casefold() for value in item_categories):
        item_categories.append(name)
    item["categories"] = item_categories


def remove_category_from_item(item: dict, category: str) -> None:
    name = normalize_category_name(category)
    if not name:
        return

    if name in TITLE_STATUS_BY_CATEGORY:
        if get_title_status(item) == TITLE_STATUS_BY_CATEGORY[name]:
            set_title_status(item, TITLE_STATUS_NONE)
        return

    item_categories = normalize_categories(
        item.get("categories", []),
        include_defaults=False,
        allow_assignable_system=True,
    )
    item_categories = [value for value in item_categories if value not in MANAGED_TITLE_CATEGORIES]
    item["categories"] = [value for value in item_categories if value.casefold() != name.casefold()]


def save_library(data_dir: Path, library: dict) -> None:
    data_dir.mkdir(parents=True, exist_ok=True)
    (data_dir / "covers").mkdir(parents=True, exist_ok=True)
    library_path = data_dir / "library.json"
    temp_path = temp_json_path(library_path)
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(library, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    replace_file_with_retry(temp_path, library_path)


def import_favorite_guard_path(data_dir: Path) -> Path:
    return data_dir / "import-favorite-guard.json"


def load_import_favorite_guard(data_dir: Path) -> set[str]:
    path = import_favorite_guard_path(data_dir)
    if not path.exists():
        return set()

    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        return set()

    now = time.time()
    guarded: set[str] = set()
    if isinstance(data, dict):
        for item_id, expires_at in data.items():
            try:
                if float(expires_at) > now:
                    guarded.add(str(item_id))
            except (TypeError, ValueError):
                continue
    return guarded


def save_import_favorite_guard(data_dir: Path, guarded_ids: set[str]) -> None:
    path = import_favorite_guard_path(data_dir)
    if not guarded_ids:
        try:
            path.unlink()
        except FileNotFoundError:
            pass
        return

    data_dir.mkdir(parents=True, exist_ok=True)
    expires_at = time.time() + IMPORT_FAVORITE_GUARD_SECONDS
    payload = {item_id: expires_at for item_id in sorted(guarded_ids)}
    temp_path = temp_json_path(path)
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    replace_file_with_retry(temp_path, path)


def add_import_favorite_guard(data_dir: Path, item_ids: set[str]) -> None:
    ids = {str(item_id) for item_id in item_ids if str(item_id)}
    if not ids:
        return
    guarded = load_import_favorite_guard(data_dir)
    guarded.update(ids)
    save_import_favorite_guard(data_dir, guarded)


def item_page_count(item: dict) -> int:
    return len(item_pages(item))


def ensure_item_page_counts(library: dict) -> bool:
    changed = False
    for item in library.get("items", []):
        current = item.get("pageCount")
        if isinstance(current, int) and current >= 0:
            continue

        try:
            item["pageCount"] = item_page_count(item)
        except Exception:
            item["pageCount"] = 0
        changed = True
    return changed


def progress_path(data_dir: Path) -> Path:
    return data_dir / "progress.json"


def ensure_progress(data_dir: Path) -> dict:
    path = progress_path(data_dir)
    if not path.exists():
        return {"version": 1, "items": {}}

    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if not isinstance(data, dict):
        return {"version": 1, "items": {}}

    data.setdefault("version", 1)
    data.setdefault("items", {})
    if not isinstance(data["items"], dict):
        data["items"] = {}
    return data


def save_progress_file(data_dir: Path, progress: dict) -> None:
    data_dir.mkdir(parents=True, exist_ok=True)
    target_path = progress_path(data_dir)
    temp_path = temp_json_path(target_path)
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(progress, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    replace_file_with_retry(temp_path, target_path)


def safe_data_child(data_dir: Path, relative_path: str | Path) -> Path | None:
    if not relative_path:
        return None

    path = Path(str(relative_path))
    if path.is_absolute():
        return None

    data_root = data_dir.resolve()
    resolved = (data_root / path).resolve()
    try:
        resolved.relative_to(data_root)
    except ValueError:
        return None
    return resolved


def clean_path_segment(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_-]", "_", str(value))
    return cleaned or "default"


def session_item_dir(data_dir: Path, session_id: str, item_id: str) -> Path:
    relative = Path("session-cache") / clean_path_segment(session_id) / clean_path_segment(item_id)
    path = safe_data_child(data_dir, relative)
    if path is None:
        raise RuntimeError("会话缓存路径无效。")
    return path


def clear_session_cache(data_dir: Path, session_id: str | None = None) -> dict:
    if session_id:
        target = safe_data_child(data_dir, Path("session-cache") / clean_path_segment(session_id))
    else:
        target = safe_data_child(data_dir, "session-cache")

    if target and target.exists():
        shutil.rmtree(target)

    return {
        "cleared": str(target) if target else "",
    }


def save_cover(image: Image.Image, cover_path: Path) -> None:
    cover_path.parent.mkdir(parents=True, exist_ok=True)

    if getattr(image, "is_animated", False):
        image.seek(0)

    try:
        image.draft("RGB", COVER_SIZE)
    except Exception:
        pass

    image = ImageOps.exif_transpose(image)
    image = image.convert("RGBA")
    image.thumbnail(COVER_SIZE, Image.Resampling.LANCZOS)

    canvas = Image.new("RGB", COVER_SIZE, COVER_BACKGROUND)
    left = (COVER_SIZE[0] - image.width) // 2
    top = (COVER_SIZE[1] - image.height) // 2
    canvas.paste(image, (left, top), image)
    canvas.save(cover_path, "PNG", compress_level=1)


def save_cover_from_file(image_path: Path, cover_path: Path) -> None:
    with Image.open(image_path) as image:
        save_cover(image, cover_path)


def save_cover_from_bytes(data: bytes, cover_path: Path) -> None:
    with Image.open(io.BytesIO(data)) as image:
        save_cover(image, cover_path)


def save_reader_image(image: Image.Image, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if getattr(image, "is_animated", False):
        image.seek(0)

    image = ImageOps.exif_transpose(image)
    image = image.convert("RGBA")
    canvas = Image.new("RGB", image.size, READER_BACKGROUND)
    canvas.paste(image, (0, 0), image)
    if output_path.suffix.casefold() in {".jpg", ".jpeg"}:
        canvas.save(output_path, "JPEG", quality=92, optimize=False, progressive=False)
    else:
        canvas.save(output_path, "PNG", optimize=True)


def save_reader_image_from_file(image_path: Path, output_path: Path) -> None:
    with Image.open(image_path) as image:
        save_reader_image(image, output_path)


def save_reader_image_from_bytes(data: bytes, output_path: Path) -> None:
    with Image.open(io.BytesIO(data)) as image:
        save_reader_image(image, output_path)


def decode_stdout(data: bytes) -> str:
    encodings = ["utf-8-sig", locale.getpreferredencoding(False), "mbcs"]
    for encoding in encodings:
        try:
            return data.decode(encoding)
        except (LookupError, UnicodeDecodeError):
            continue
    return data.decode("utf-8", errors="replace")


class ExternalArchiveReader:
    name = "external"

    def list_files(self, archive_path: Path, password: str | None = None) -> list[str]:
        raise NotImplementedError

    def read_file(self, archive_path: Path, member: str, password: str | None = None) -> bytes:
        raise NotImplementedError


class SevenZipArchiveReader(ExternalArchiveReader):
    name = "7z"

    def __init__(self, executable: str) -> None:
        self.executable = executable

    def password_args(self, password: str | None) -> list[str]:
        if password is None:
            return []
        return [f"-p{password}"]

    def password_error(self, stdout: bytes, stderr: bytes) -> bool:
        text = (decode_stdout(stdout) + "\n" + decode_stdout(stderr)).casefold()
        password_markers = (
            "enter password",
            "encrypted",
            "wrong password",
            "can not open encrypted archive",
            "data error in encrypted file",
            "break signaled",
            "headers error",
            "密码",
            "パスワード",
        )
        return any(marker in text for marker in password_markers)

    def list_files(self, archive_path: Path, password: str | None = None) -> list[str]:
        try:
            proc = subprocess.run(
                [self.executable, "l", "-slt", *self.password_args(password), str(archive_path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL,
                check=False,
                timeout=EXTERNAL_ARCHIVE_LIST_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as exc:
            raise ArchivePasswordRequiredError(f"需要密码：{archive_path.name}") from exc

        if proc.returncode != 0:
            if self.password_error(proc.stdout, proc.stderr):
                if password:
                    raise ArchivePasswordIncorrectError("密码不正确，或该压缩包仍无法解密。")
                raise ArchivePasswordRequiredError(f"需要密码：{archive_path.name}")
            message = decode_stdout(proc.stderr).strip() or "7z 无法读取该压缩包。"
            raise RuntimeError(message)

        files: list[str] = []
        block: dict[str, str] = {}
        has_encrypted_files = False
        for raw_line in decode_stdout(proc.stdout).splitlines() + [""]:
            line = raw_line.strip()
            if not line:
                path = block.get("Path")
                is_folder = block.get("Folder") == "+"
                if path and not is_folder and path != str(archive_path):
                    if block.get("Encrypted") == "+":
                        has_encrypted_files = True
                    files.append(path)
                block = {}
                continue
            if " = " in line:
                key, value = line.split(" = ", 1)
                block[key] = value
        if has_encrypted_files and password is None:
            raise ArchivePasswordRequiredError(f"需要密码：{archive_path.name}")
        return files

    def read_file(self, archive_path: Path, member: str, password: str | None = None) -> bytes:
        try:
            proc = subprocess.run(
                [self.executable, "e", "-y", "-so", *self.password_args(password), str(archive_path), member],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL,
                check=False,
                timeout=EXTERNAL_ARCHIVE_EXTRACT_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as exc:
            raise ArchivePasswordRequiredError(f"需要密码：{archive_path.name}") from exc

        if proc.returncode != 0:
            if self.password_error(proc.stdout, proc.stderr):
                if password:
                    raise ArchivePasswordIncorrectError("密码不正确，或该压缩包仍无法解密。")
                raise ArchivePasswordRequiredError(f"需要密码：{archive_path.name}")
            message = decode_stdout(proc.stderr).strip() or f"7z 无法提取 {member}"
            raise RuntimeError(message)
        return proc.stdout


def find_seven_zip_executable() -> str | None:
    for name in ("7z", "7zz", "7za"):
        executable = shutil.which(name)
        if executable:
            return executable

    for path in SEVEN_ZIP_COMMON_PATHS:
        if path.exists() and path.is_file():
            return str(path)

    return None


def get_external_reader() -> ExternalArchiveReader | None:
    executable = find_seven_zip_executable()
    if executable:
        return SevenZipArchiveReader(executable)

    return None


def zip_password_bytes(password: str | None) -> bytes | None:
    if password is None:
        return None
    return password.encode("utf-8")


def read_zip_member(archive: zipfile.ZipFile, member: str, password: str | None = None) -> bytes:
    try:
        with archive.open(member, pwd=zip_password_bytes(password)) as handle:
            return handle.read()
    except RuntimeError as exc:
        text = str(exc).casefold()
        if "password required" in text or "bad password" in text or "encrypted" in text:
            if password:
                raise ArchivePasswordIncorrectError("密码不正确，或该压缩包仍无法解密。") from exc
            raise ArchivePasswordRequiredError("需要密码。") from exc
        raise


def progress_item_payload(item: dict) -> dict:
    return {
        "id": item.get("id", ""),
        "name": item.get("name", ""),
        "kind": item.get("kind", ""),
        "sourcePath": item.get("sourcePath", ""),
        "comicPath": item.get("comicPath", ""),
        "internalPath": item.get("internalPath", ""),
        "cover": item.get("cover", ""),
        "pageCount": item.get("pageCount", 0),
        "categories": item.get("categories", []),
        "titleStatus": item.get("titleStatus", ""),
        "tagStatus": item.get("tagStatus", ""),
        "requiresPassword": bool(item.get("requiresPassword", False)),
        "passwordKey": item.get("passwordKey", ""),
        "addedAt": item.get("addedAt", ""),
        "titleSelected": bool(item.get("titleSelected", False)),
        "tagClassifiedAt": item.get("tagClassifiedAt", ""),
    }


def append_progress_event(progress_file: Path | None, event_type: str, message: str = "", **fields: object) -> None:
    if progress_file is None:
        return

    progress_file.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "time": utc_now(),
        "type": event_type,
        "message": message,
    }
    payload.update(fields)
    with progress_file.open("a", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
        handle.flush()


def add_item(
    *,
    library: dict,
    existing_ids: set[str],
    result: dict,
    item: dict,
    progress_file: Path | None = None,
    on_added=None,
    progress_type: str = "added",
    progress_message: str | None = None,
) -> bool:
    if item["id"] in existing_ids:
        result["skipped"].append(
            {
                "name": item["name"],
                "reason": "duplicate",
            }
        )
        append_progress_event(progress_file, "skipped", f"跳过重复：{item['name']}", name=item["name"], reason="duplicate")
        return False

    library["items"].append(item)
    existing_ids.add(item["id"])
    result["added"].append(
        {
            "id": item["id"],
            "name": item["name"],
            "requiresPassword": bool(item.get("requiresPassword", False)),
        }
    )
    if on_added is not None:
        on_added(item)
    append_progress_event(progress_file, progress_type, progress_message or f"已添加：{item['name']}", item=progress_item_payload(item))
    return True


def title_sample_indexes(
    page_count: int,
    head_count: int = TITLE_SAMPLE_HEAD_COUNT,
    tail_count: int = TITLE_SAMPLE_TAIL_COUNT,
) -> list[int]:
    indexes: list[int] = []
    for index in range(min(head_count, page_count)):
        indexes.append(index)

    tail_start = max(0, page_count - tail_count)
    for index in range(tail_start, page_count):
        if index not in indexes:
            indexes.append(index)

    return indexes


def image_has_ocr_detail(image: Image.Image) -> bool:
    sample = ImageOps.grayscale(ImageOps.exif_transpose(image.copy()))
    sample.thumbnail((256, 256), Image.Resampling.BILINEAR)
    stat = ImageStat.Stat(sample)
    return bool(stat.stddev and stat.stddev[0] >= 8)


def save_ocr_image(image: Image.Image, output_path: Path, max_dimension: int = OCR_MAX_IMAGE_DIMENSION) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    image = ImageOps.exif_transpose(image)
    if not image_has_ocr_detail(image):
        raise RuntimeError("页面图像信息过少，跳过 OCR。")

    if image.mode in ("RGBA", "LA") or (image.mode == "P" and "transparency" in image.info):
        canvas = Image.new("RGB", image.size, (255, 255, 255))
        canvas.paste(image.convert("RGBA"), mask=image.convert("RGBA").split()[-1])
        image = canvas
    elif image.mode != "RGB":
        image = image.convert("RGB")

    longest_side = max(image.size)
    if longest_side > max_dimension:
        image.thumbnail((max_dimension, max_dimension), Image.Resampling.LANCZOS)

    image.save(output_path, "PNG", optimize=True)


def save_ocr_image_from_file(
    image_path: Path,
    output_path: Path,
    max_dimension: int = OCR_MAX_IMAGE_DIMENSION,
) -> None:
    with Image.open(image_path) as image:
        save_ocr_image(image, output_path, max_dimension=max_dimension)


def save_ocr_image_from_bytes(
    data: bytes,
    output_path: Path,
    max_dimension: int = OCR_MAX_IMAGE_DIMENSION,
) -> None:
    with Image.open(io.BytesIO(data)) as image:
        save_ocr_image(image, output_path, max_dimension=max_dimension)


@contextlib.contextmanager
def suppress_process_output():
    try:
        stdout_fd = sys.stdout.fileno()
        stderr_fd = sys.stderr.fileno()
        saved_stdout_fd = os.dup(stdout_fd)
        saved_stderr_fd = os.dup(stderr_fd)
    except (AttributeError, OSError):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            yield
        return

    try:
        with open(os.devnull, "w", encoding="utf-8") as devnull:
            sys.stdout.flush()
            sys.stderr.flush()
            os.dup2(devnull.fileno(), stdout_fd)
            os.dup2(devnull.fileno(), stderr_fd)
            stdout_buffer = io.StringIO()
            stderr_buffer = io.StringIO()
            with contextlib.redirect_stdout(stdout_buffer), contextlib.redirect_stderr(stderr_buffer):
                yield
    finally:
        sys.stdout.flush()
        sys.stderr.flush()
        os.dup2(saved_stdout_fd, stdout_fd)
        os.dup2(saved_stderr_fd, stderr_fd)
        os.close(saved_stdout_fd)
        os.close(saved_stderr_fd)


def paddle_ocr_user_home(data_dir: Path) -> Path:
    return data_dir / "paddle-user"


def directory_has_any_file(path: Path) -> bool:
    if not path.exists():
        return False
    try:
        return any(child.is_file() for child in path.rglob("*"))
    except OSError:
        return False


def paddle_ocr_status(data_dir: Path, initialize: bool = False) -> dict:
    global _PADDLE_OCR_ERROR

    cache_path = paddle_ocr_user_home(data_dir)
    result = {
        "available": False,
        "installed": False,
        "initialized": False,
        "cachePath": str(cache_path),
        "cacheExists": directory_has_any_file(cache_path),
        "initializeRequested": bool(initialize),
        "installCommand": f'"{sys.executable}" -m pip install paddleocr paddlepaddle',
        "message": "",
        "error": "",
    }

    try:
        with paddle_ocr_environment(data_dir):
            with suppress_process_output():
                import paddle                              
                from paddleocr import PaddleOCR                              
        result["installed"] = True
    except Exception as exc:
        result["error"] = f"PaddleOCR 未安装或无法导入：{exc}"
        result["message"] = "需要先安装 PaddleOCR 和 PaddlePaddle。"
        return result

    if not initialize:
        result["available"] = True
        result["message"] = "PaddleOCR 已安装。"
        return result

    ocr = get_paddle_ocr(data_dir, allow_download=True)
    if ocr is None:
        result["error"] = _PADDLE_OCR_ERROR or "PaddleOCR 初始化失败。"
        result["message"] = result["error"]
        return result

    result["available"] = True
    result["initialized"] = True
    result["cacheExists"] = directory_has_any_file(cache_path)
    result["message"] = "PaddleOCR 已初始化。"
    return result


def configured_paddle_threads() -> int:
    value = os.environ.get("MANGA_SHELF_PADDLE_THREADS", "").strip()
    if value:
        try:
            return max(1, min(32, int(value)))
        except ValueError:
            pass

    cpu_count = os.cpu_count() or 4
    return max(4, min(16, cpu_count))


def configured_paddle_batch_size() -> int:
    value = os.environ.get("MANGA_SHELF_PADDLE_BATCH", "").strip()
    if value:
        try:
            return max(1, min(16, int(value)))
        except ValueError:
            pass
    return PADDLE_OCR_DEFAULT_BATCH_SIZE


@contextlib.contextmanager
def paddle_ocr_environment(data_dir: Path, offline: bool = True):
    user_home = paddle_ocr_user_home(data_dir)
    user_home.mkdir(parents=True, exist_ok=True)
    (user_home / ".paddlex").mkdir(parents=True, exist_ok=True)

    threads = configured_paddle_threads()
    updates = {
        "USERPROFILE": str(user_home),
        "PADDLE_PDX_CACHE_HOME": str(user_home / ".paddlex"),
        "PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK": "True",
        "FLAGS_use_mkldnn": "0",
        "FLAGS_use_onednn": "0",
        "OMP_NUM_THREADS": str(threads),
        "MKL_NUM_THREADS": str(threads),
        "PADDLE_CPU_NUM_THREADS": str(threads),
        "TOKENIZERS_PARALLELISM": "false",
    }
    offline_keys = ("HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE")
    if offline:
        updates["HF_HUB_OFFLINE"] = "1"
        updates["TRANSFORMERS_OFFLINE"] = "1"

    original_values = {key: os.environ.get(key) for key in set(updates).union(offline_keys)}
    for key, value in updates.items():
        os.environ[key] = value
    if not offline:
        for key in offline_keys:
            os.environ.pop(key, None)

    try:
        yield
    finally:
        for key, value in original_values.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def get_paddle_ocr(data_dir: Path, allow_download: bool = False):
    global _PADDLE_OCR_INSTANCE, _PADDLE_OCR_UNAVAILABLE, _PADDLE_OCR_ERROR

    if _PADDLE_OCR_UNAVAILABLE:
        return None
    if _PADDLE_OCR_INSTANCE is not None:
        return _PADDLE_OCR_INSTANCE

    try:
        with paddle_ocr_environment(data_dir, offline=not allow_download):
            with suppress_process_output():
                try:
                    import torch              
                except Exception:
                    pass
                try:
                    import paddle

                    paddle.set_num_threads(configured_paddle_threads())
                except Exception:
                    pass
                from paddleocr import PaddleOCR                
    except Exception as exc:
        _PADDLE_OCR_ERROR = f"PaddleOCR 未安装或无法导入：{exc}"
        _PADDLE_OCR_UNAVAILABLE = True
        return None

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            with paddle_ocr_environment(data_dir, offline=not allow_download):
                with suppress_process_output():
                    _PADDLE_OCR_INSTANCE = PaddleOCR(
                        lang=PADDLE_OCR_LANG,
                        use_doc_orientation_classify=False,
                        use_doc_unwarping=False,
                        use_textline_orientation=False,
                        text_det_limit_side_len=PADDLE_OCR_DETECTION_LIMIT,
                        text_det_limit_type="max",
                        text_recognition_batch_size=configured_paddle_batch_size(),
                        enable_mkldnn=False,
                        cpu_threads=configured_paddle_threads(),
                    )
    except Exception as exc:
        _PADDLE_OCR_ERROR = f"PaddleOCR 初始化失败：{exc}"
        _PADDLE_OCR_UNAVAILABLE = True
        return None

    return _PADDLE_OCR_INSTANCE


def paddle_score_is_usable(score: object) -> bool:
    if score is None:
        return True
    try:
        return float(score) >= PADDLE_OCR_MIN_SCORE
    except (TypeError, ValueError):
        return True


def paddle_prediction_lines(prediction: object) -> list[str]:
    lines: list[str] = []

    def add_line(text: object, score: object = None) -> None:
        if not paddle_score_is_usable(score):
            return
        line = str(text or "").strip()
        if line:
            lines.append(line)

    def walk(value: object) -> None:
        if isinstance(value, dict):
            rec_texts = value.get("rec_texts")
            if isinstance(rec_texts, list):
                rec_scores = value.get("rec_scores")
                for index, text in enumerate(rec_texts):
                    score = rec_scores[index] if isinstance(rec_scores, list) and index < len(rec_scores) else None
                    add_line(text, score)

            text = value.get("text")
            if isinstance(text, str):
                add_line(text, value.get("score"))

            for key in ("result", "results", "res", "ocr_res", "data"):
                if key in value:
                    walk(value[key])
            return

        if isinstance(value, (list, tuple)):
            if len(value) >= 2 and isinstance(value[0], str) and not isinstance(value[1], (list, tuple, dict)):
                add_line(value[0], value[1])
                return

            if len(value) >= 2 and isinstance(value[1], (list, tuple)) and value[1] and isinstance(value[1][0], str):
                score = value[1][1] if len(value[1]) > 1 else None
                add_line(value[1][0], score)
                return

            for item in value:
                walk(item)

    walk(prediction)

    unique_lines: list[str] = []
    seen: set[str] = set()
    for line in lines:
        key = line.casefold()
        if key in seen:
            continue
        seen.add(key)
        unique_lines.append(line)
    return unique_lines


def run_paddle_ocr(data_dir: Path, image_paths: list[str], progress_callback=None) -> list[dict]:
    global _PADDLE_OCR_ERROR

    if not image_paths:
        return []

    if progress_callback:
        progress_callback(0, len(image_paths), "加载 PaddleOCR 模型")
    ocr = get_paddle_ocr(data_dir)
    if ocr is None:
        return []

    results = []
    total = len(image_paths)
    batch_size = configured_paddle_batch_size()
    for start in range(0, total, batch_size):
        batch_paths = image_paths[start : start + batch_size]
        end = start + len(batch_paths)
        try:
            if progress_callback:
                if len(batch_paths) == 1:
                    message = f"PaddleOCR 识别样张 {start + 1}/{total}"
                else:
                    message = f"PaddleOCR 批量识别样张 {start + 1}-{end}/{total}"
                progress_callback(start, total, message)
            with paddle_ocr_environment(data_dir):
                with suppress_process_output():
                    prediction = ocr.predict(batch_paths)
        except Exception as exc:
            _PADDLE_OCR_ERROR = f"PaddleOCR 识别失败：{exc}"
            continue

        if isinstance(prediction, list) and len(prediction) == len(batch_paths):
            predictions = prediction
        else:
            predictions = [prediction]

        for offset, image_path in enumerate(batch_paths):
            single_prediction = predictions[offset] if offset < len(predictions) else None
            lines = paddle_prediction_lines(single_prediction)
            results.append(
                {
                    "path": image_path,
                    "text": "\n".join(lines),
                    "lines": lines,
                }
            )

        if progress_callback:
            progress_callback(end, total, f"PaddleOCR 完成样张 {end}/{total}")

    return results


def huggingface_cache_root() -> Path:
    hf_home = os.environ.get("HF_HOME")
    if hf_home:
        return Path(hf_home) / "hub"

    user_profile = os.environ.get("USERPROFILE")
    if user_profile:
        return Path(user_profile) / ".cache" / "huggingface" / "hub"

    return Path.home() / ".cache" / "huggingface" / "hub"


def manga_ocr_snapshot_is_complete(snapshot: Path) -> bool:
    required_files = {
        "config.json",
        "preprocessor_config.json",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "vocab.txt",
    }
    if not all((snapshot / name).is_file() for name in required_files):
        return False
    return (snapshot / "model.safetensors").is_file() or (snapshot / "pytorch_model.bin").is_file()


def find_local_manga_ocr_model_path() -> Path | None:
    env_path = os.environ.get("MANGA_SHELF_MANGA_OCR_MODEL")
    if env_path:
        candidate = Path(env_path)
        if candidate.exists() and manga_ocr_snapshot_is_complete(candidate):
            return candidate

    model_root = huggingface_cache_root() / "models--kha-white--manga-ocr-base" / "snapshots"
    if not model_root.exists():
        return None

    candidates = [path for path in model_root.iterdir() if path.is_dir() and manga_ocr_snapshot_is_complete(path)]
    if not candidates:
        return None

    candidates.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    return candidates[0]


def get_manga_ocr():
    global _MANGA_OCR_INSTANCE, _MANGA_OCR_UNAVAILABLE, _MANGA_OCR_ERROR

    if _MANGA_OCR_UNAVAILABLE:
        return None
    if _MANGA_OCR_INSTANCE is not None:
        return _MANGA_OCR_INSTANCE

    os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

    model_path = find_local_manga_ocr_model_path()
    if model_path is None:
        _MANGA_OCR_ERROR = "Manga-OCR 模型未完整缓存到本机。请联网完成一次模型缓存后再离线识别。"
        _MANGA_OCR_UNAVAILABLE = True
        return None

    try:
        with suppress_process_output():
            from manga_ocr import MangaOcr                
    except Exception as exc:
        _MANGA_OCR_ERROR = f"Manga-OCR 未安装或无法导入：{exc}"
        _MANGA_OCR_UNAVAILABLE = True
        return None

    try:
        from loguru import logger

        logger.remove()
    except Exception:
        pass

    try:
        from transformers.utils import logging as transformers_logging

        transformers_logging.set_verbosity_error()
    except Exception:
        pass

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            with suppress_process_output():
                _MANGA_OCR_INSTANCE = MangaOcr(str(model_path), force_cpu=True)
    except Exception as exc:
        _MANGA_OCR_ERROR = f"Manga-OCR 初始化失败：{exc}"
        _MANGA_OCR_UNAVAILABLE = True
        return None

    return _MANGA_OCR_INSTANCE


def split_manga_ocr_text(text: str) -> list[str]:
    cleaned = str(text or "").strip()
    if not cleaned:
        return []

    lines = [line.strip() for line in cleaned.splitlines() if line.strip()]
    if lines:
        return lines

    return [cleaned]


def run_manga_ocr(image_paths: list[str], progress_callback=None) -> list[dict]:
    if not image_paths:
        return []

    if progress_callback:
        progress_callback(0, len(image_paths), "加载 Manga-OCR 模型")
    ocr = get_manga_ocr()
    if ocr is None:
        return []

    results = []
    total = len(image_paths)
    for index, image_path in enumerate(image_paths):
        try:
            if progress_callback:
                progress_callback(index, total, f"Manga-OCR 识别样张 {index + 1}/{total}")
            with suppress_process_output():
                text = ocr(image_path)
        except Exception:
            continue

        lines = split_manga_ocr_text(str(text or ""))
        if progress_callback:
            progress_callback(index + 1, total, f"Manga-OCR 完成样张 {index + 1}/{total}")
        results.append(
            {
                "path": image_path,
                "text": "\n".join(lines),
                "lines": lines,
            }
        )

    return results


def write_ocr_samples_for_item(
    item: dict,
    temp_dir: Path,
    *,
    head_count: int = TITLE_SAMPLE_HEAD_COUNT,
    tail_count: int = TITLE_SAMPLE_TAIL_COUNT,
    max_dimension: int = OCR_MAX_IMAGE_DIMENSION,
    progress_callback=None,
) -> tuple[list[dict], int]:
    pages = item_pages(item)
    indexes = title_sample_indexes(len(pages), head_count=head_count, tail_count=tail_count)
    samples: list[dict] = []
    total = len(indexes)

    def report_sample_start(position: int, page_index: int) -> None:
        if progress_callback:
            progress_callback(0, total, f"抽取样张 {position + 1}/{total}（第{page_index + 1}页）")

    def report_sample_done(position: int, page_index: int) -> None:
        if progress_callback:
            progress_callback(0, total, f"已抽取样张 {position + 1}/{total}（第{page_index + 1}页）")

    if item.get("kind") == "folder":
        for position, page_index in enumerate(indexes):
            page = pages[page_index]
            output_path = temp_dir / f"{page_index:05d}.png"
            try:
                report_sample_start(position, page_index)
                save_ocr_image_from_file(Path(page["path"]), output_path, max_dimension=max_dimension)
            except Exception:
                continue
            report_sample_done(position, page_index)
            samples.append(
                {
                    "path": str(output_path),
                    "pageIndex": page_index,
                    "pageLabel": f"第{page_index + 1}页",
                }
            )
        return samples, len(pages)

    if item.get("kind") != "archive":
        return samples, len(pages)

    archive_path = Path(str(item.get("sourcePath", "")))
    if archive_path.suffix.casefold() == ".zip":
        with zipfile.ZipFile(archive_path) as archive:
            for position, page_index in enumerate(indexes):
                page = pages[page_index]
                output_path = temp_dir / f"{page_index:05d}.png"
                try:
                    report_sample_start(position, page_index)
                    with archive.open(page["member"]) as handle:
                        save_ocr_image_from_bytes(handle.read(), output_path, max_dimension=max_dimension)
                except Exception:
                    continue
                report_sample_done(position, page_index)
                samples.append(
                    {
                        "path": str(output_path),
                        "pageIndex": page_index,
                        "pageLabel": f"第{page_index + 1}页",
                    }
                )
        return samples, len(pages)

    reader = get_external_reader()
    if reader is None:
        return samples, len(pages)

    for position, page_index in enumerate(indexes):
        page = pages[page_index]
        output_path = temp_dir / f"{page_index:05d}.png"
        try:
            report_sample_start(position, page_index)
            save_ocr_image_from_bytes(
                reader.read_file(archive_path, page["member"]),
                output_path,
                max_dimension=max_dimension,
            )
        except Exception:
            continue
        report_sample_done(position, page_index)
        samples.append(
            {
                "path": str(output_path),
                "pageIndex": page_index,
                "pageLabel": f"第{page_index + 1}页",
            }
        )

    return samples, len(pages)


TITLE_NOISE_RE = re.compile(
    r"(https?://|www\.|pixiv|twitter|x\.com|fanbox|patreon|copyright|all rights|sample|page\s*\d|^\d+$)",
    re.IGNORECASE,
)


def clean_ocr_line(value: object) -> str:
    text = normalize_title_candidate_name(value)
    text = re.sub(r"\s+", " ", text)
    return text


def useful_title_char_count(text: str) -> int:
    count = 0
    for char in text:
        if char.isalnum() or "\u3040" <= char <= "\u30ff" or "\u3400" <= char <= "\u9fff":
            count += 1
    return count


def has_cjk_or_kana(text: str) -> bool:
    return contains_cjk_or_kana(text)


def title_candidate_score(text: str, page_index: int, line_index: int, page_count: int, span: int) -> float:
    text_len = len(text)
    if text_len < 2 or text_len > 80:
        return -1
    if TITLE_NOISE_RE.search(text):
        return -1

    useful_count = useful_title_char_count(text)
    if useful_count < 2 or useful_count / max(text_len, 1) < 0.45:
        return -1

    score = 100.0
    if page_index < TITLE_SAMPLE_HEAD_COUNT:
        score += 45 - (page_index * 4)
    if page_count - page_index <= TITLE_SAMPLE_TAIL_COUNT:
        score += 35 - ((page_count - page_index - 1) * 3)
    if has_cjk_or_kana(text):
        score += 12
    if 4 <= text_len <= 36:
        score += 10
    elif text_len > 50:
        score -= 15

    punctuation_count = sum(1 for char in text if not char.isalnum() and not char.isspace())
    score -= min(25, punctuation_count * 2)
    score -= min(30, line_index * 2)
    score -= max(0, span - 1) * 4
    return score


def ocr_result_lines(result: dict) -> list[str]:
    lines = result.get("lines")
    if isinstance(lines, list):
        cleaned = [clean_ocr_line(line) for line in lines]
    else:
        cleaned = [clean_ocr_line(line) for line in str(result.get("text", "")).splitlines()]
    return [line for line in cleaned if line]


def build_title_candidates(samples: list[dict], ocr_results: list[dict], page_count: int) -> list[dict]:
    sample_by_path = {str(sample["path"]): sample for sample in samples}
    best_by_key: dict[str, dict] = {}

    for result in ocr_results:
        path = str(result.get("path", ""))
        sample = sample_by_path.get(path)
        if not sample:
            continue

        page_index = int(sample["pageIndex"])
        lines = ocr_result_lines(result)
        if not lines:
            continue

        for line_index, line in enumerate(lines):
            for span in (1, 2, 3):
                if line_index + span > len(lines):
                    continue

                candidate_text = "".join(lines[line_index : line_index + span]) if span > 1 else line
                candidate_text = normalize_title_candidate_name(candidate_text)
                if not candidate_text:
                    continue

                score = title_candidate_score(candidate_text, page_index, line_index, page_count, span)
                if score < 0:
                    continue

                key = normalize_title_key(candidate_text)
                existing = best_by_key.get(key)
                if existing and existing.get("score", 0) >= score:
                    continue

                best_by_key[key] = {
                    "name": candidate_text,
                    "pageIndex": page_index,
                    "pageLabel": sample.get("pageLabel", f"第{page_index + 1}页"),
                    "score": round(score, 2),
                }

    candidates = sorted(best_by_key.values(), key=lambda candidate: candidate.get("score", 0), reverse=True)
    return normalize_title_candidates(candidates[:TITLE_CANDIDATE_LIMIT])


def recognize_title_candidates_for_item(data_dir: Path, item: dict, progress_callback=None) -> list[dict]:
    def report(current: int, total: int, message: str) -> None:
        if progress_callback:
            progress_callback(current, total, message)

    def recognize_from_samples(samples: list[dict], page_count: int) -> tuple[list[dict], list[dict]]:
        image_paths = [sample["path"] for sample in samples]
        paddle_results = run_paddle_ocr(data_dir, image_paths, progress_callback=report)
        candidates = build_title_candidates(samples, paddle_results, page_count)
        return candidates, paddle_results

    with tempfile.TemporaryDirectory(prefix="manga-shelf-ocr-") as temp:
        temp_dir = Path(temp)
        report(0, 0, "抽取前5页与后5页样张")
        samples, page_count = write_ocr_samples_for_item(
            item,
            temp_dir / "samples",
            head_count=TITLE_SAMPLE_HEAD_COUNT,
            tail_count=TITLE_SAMPLE_TAIL_COUNT,
            max_dimension=OCR_MAX_IMAGE_DIMENSION,
            progress_callback=report,
        )
        if not samples:
            return []

        candidates, paddle_results = recognize_from_samples(samples, page_count)
        if candidates:
            return candidates

        if not paddle_results and _PADDLE_OCR_UNAVAILABLE:
            raise RuntimeError(_PADDLE_OCR_ERROR or "PaddleOCR 不可用。")

        return []


def apply_title_candidates(item: dict, candidates: list[dict]) -> bool:
    normalized = normalize_title_candidates(candidates)
    if not normalized:
        return False

    original_name = str(item.get("name", ""))
    item["titleOriginalName"] = str(item.get("titleOriginalName") or original_name)
    item["titleCandidates"] = normalized
    item["titleSelected"] = False
    item["titleDetectedAt"] = utc_now()
    item["name"] = normalized[0]["name"]
    add_category_to_item(item, PENDING_TITLE_CATEGORY)
    remove_category_from_item(item, TITLE_RECOGNIZING_CATEGORY)
    return True


def finish_title_recognition_without_candidates(item: dict) -> None:
    item["titleCandidates"] = normalize_title_candidates(item.get("titleCandidates", []))
    item["titleSelected"] = bool(item.get("titleSelected", False)) if item["titleCandidates"] else False
    item["titleDetectedAt"] = utc_now()
    add_category_to_item(item, PENDING_TITLE_CATEGORY)
    remove_category_from_item(item, TITLE_RECOGNIZING_CATEGORY)


def finish_title_recognition_name_ok(item: dict) -> None:
    item["titleCandidates"] = normalize_title_candidates(item.get("titleCandidates", []))
    item["titleSelected"] = bool(item.get("titleSelected", False)) if item["titleCandidates"] else False
    remove_category_from_item(item, TITLE_RECOGNIZING_CATEGORY)
    remove_category_from_item(item, PENDING_TITLE_CATEGORY)


def recognize_titles_for_items(data_dir: Path, library: dict, item_ids: list[str], progress_callback=None) -> dict:
    id_set = {str(item_id) for item_id in item_ids if str(item_id)}
    result = {"updated": [], "skipped": [], "errors": []}

    if not id_set:
        return result

    for item in library.get("items", []):
        if str(item.get("id", "")) not in id_set:
            continue

        if not name_needs_title_recognition(item.get("name", "")):
            finish_title_recognition_name_ok(item)
            result["skipped"].append({"id": item.get("id", ""), "reason": "name_ok"})
            continue

        try:
            candidates = recognize_title_candidates_for_item(data_dir, item, progress_callback=progress_callback)
        except Exception as exc:                                                              
            result["errors"].append({"id": item.get("id", ""), "message": str(exc)})
            continue

        if not candidates:
            finish_title_recognition_without_candidates(item)
            result["skipped"].append({"id": item.get("id", ""), "reason": "no_candidates"})
            continue

        apply_title_candidates(item, candidates)
        result["updated"].append(
            {
                "id": item.get("id", ""),
                "name": item.get("name", ""),
                "candidateCount": len(item.get("titleCandidates", [])),
            }
        )

    return result


def scan_folder(
    source_root: Path,
    data_dir: Path,
    library: dict,
    existing_ids: set[str],
    result: dict,
    progress_file: Path | None = None,
    on_added=None,
) -> int:
    added_before = len(result["added"])
    data_root = data_dir.resolve()
    ignored_dir_names = {".git", "__pycache__", "node_modules", ".venv", "venv"}

    for dirpath, dirnames, filenames in os.walk(source_root):
        current_dir = Path(dirpath)
        if path_is_relative_to(current_dir, data_root):
            dirnames[:] = []
            continue

        kept_dirnames = []
        for dirname in dirnames:
            child_dir = current_dir / dirname
            if dirname in ignored_dir_names:
                continue
            if path_is_relative_to(child_dir, data_root):
                continue
            kept_dirnames.append(dirname)
        kept_dirnames.sort(key=natural_key)
        dirnames[:] = kept_dirnames

        image_names = sorted((name for name in filenames if is_image(name)), key=natural_key)
        if not image_names:
            continue

        comic_dir = current_dir
        unique_key = "folder:" + normcase_path(comic_dir)
        item_id = stable_id(unique_key)
        cover_rel = Path("covers") / f"{item_id}.png"
        cover_path = data_dir / cover_rel

        if item_id not in existing_ids:
            save_cover_from_file(comic_dir / image_names[0], cover_path)

        item = {
            "id": item_id,
            "name": display_name_for_folder(source_root, comic_dir),
            "kind": "folder",
            "sourcePath": str(source_root.resolve()),
            "comicPath": str(comic_dir.resolve()),
            "internalPath": "",
            "cover": cover_rel.as_posix(),
            "categories": [],
            "pageCount": len(image_names),
            "addedAt": utc_now(),
        }
        add_item(
            library=library,
            existing_ids=existing_ids,
            result=result,
            item=item,
            progress_file=progress_file,
            on_added=on_added,
        )

    return len(result["added"]) - added_before


def grouped_archive_images(members: list[str]) -> dict[str, list[tuple[str, str]]]:
    grouped: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for original in members:
        normalized = normalize_internal_path(original)
        if not normalized or normalized.startswith("__MACOSX/"):
            continue
        if not is_image(normalized):
            continue
        grouped[parent_internal_path(normalized)].append((normalized, original))

    for images in grouped.values():
        images.sort(key=lambda pair: natural_key(pair[0]))
    return dict(grouped)


def scan_zip_archive(
    archive_path: Path,
    data_dir: Path,
    library: dict,
    existing_ids: set[str],
    result: dict,
    progress_file: Path | None = None,
    on_added=None,
    password: str | None = None,
) -> int:
    added_before = len(result["added"])
    covers_dir = data_dir / "covers"

    append_progress_event(progress_file, "archive", f"读取压缩包目录：{archive_path.name}", path=str(archive_path))
    with zipfile.ZipFile(archive_path) as archive:
        members = [info.filename for info in archive.infolist() if not info.is_dir()]
        grouped = grouped_archive_images(members)

        for internal_dir in sorted(grouped, key=natural_key):
            images = grouped[internal_dir]
            unique_key = f"archive:{normcase_path(archive_path)}|{normalize_internal_path(internal_dir)}"
            item_id = stable_id(unique_key)
            cover_rel = Path("covers") / f"{item_id}.png"
            cover_path = data_dir / cover_rel

            if item_id not in existing_ids:
                _, original_member = images[0]
                append_progress_event(progress_file, "cover", f"提取封面：{display_name_for_archive(archive_path, internal_dir)}", path=str(archive_path))
                save_cover_from_bytes(read_zip_member(archive, original_member, password), cover_path)

            item = {
                "id": item_id,
                "name": display_name_for_archive(archive_path, internal_dir),
                "kind": "archive",
                "sourcePath": str(archive_path.resolve()),
                "comicPath": "",
                "internalPath": normalize_internal_path(internal_dir),
                "cover": cover_rel.as_posix(),
                "categories": [],
                "pageCount": len(images),
                "addedAt": utc_now(),
            }
            add_item(
                library=library,
                existing_ids=existing_ids,
                result=result,
                item=item,
                progress_file=progress_file,
                on_added=on_added,
            )

    return len(result["added"]) - added_before


def scan_external_archive(
    archive_path: Path,
    data_dir: Path,
    library: dict,
    existing_ids: set[str],
    result: dict,
    progress_file: Path | None = None,
    on_added=None,
    password: str | None = None,
) -> int:
    reader = get_external_reader()
    if reader is None:
        raise RuntimeError("未找到 7z/7zz/7za 或 7-Zip 默认安装路径，无法读取 rar 或 7z。")

    added_before = len(result["added"])
    append_progress_event(progress_file, "archive", f"读取压缩包目录：{archive_path.name}", path=str(archive_path))
    members = reader.list_files(archive_path, password=password)
    grouped = grouped_archive_images(members)

    for internal_dir in sorted(grouped, key=natural_key):
        images = grouped[internal_dir]
        unique_key = f"archive:{normcase_path(archive_path)}|{normalize_internal_path(internal_dir)}"
        item_id = stable_id(unique_key)
        cover_rel = Path("covers") / f"{item_id}.png"
        cover_path = data_dir / cover_rel

        if item_id not in existing_ids:
            _, original_member = images[0]
            append_progress_event(progress_file, "cover", f"提取封面：{display_name_for_archive(archive_path, internal_dir)}", path=str(archive_path))
            save_cover_from_bytes(reader.read_file(archive_path, original_member, password=password), cover_path)

        item = {
            "id": item_id,
            "name": display_name_for_archive(archive_path, internal_dir),
            "kind": "archive",
            "sourcePath": str(archive_path.resolve()),
            "comicPath": "",
            "internalPath": normalize_internal_path(internal_dir),
            "cover": cover_rel.as_posix(),
            "categories": [],
            "pageCount": len(images),
            "addedAt": utc_now(),
        }
        add_item(
            library=library,
            existing_ids=existing_ids,
            result=result,
            item=item,
            progress_file=progress_file,
            on_added=on_added,
        )

    return len(result["added"]) - added_before


def scan_archive(
    archive_path: Path,
    data_dir: Path,
    library: dict,
    existing_ids: set[str],
    result: dict,
    progress_file: Path | None = None,
    on_added=None,
    password: str | None = None,
) -> int:
    if archive_path.suffix.casefold() == ".zip":
        return scan_zip_archive(archive_path, data_dir, library, existing_ids, result, progress_file=progress_file, on_added=on_added, password=password)
    return scan_external_archive(archive_path, data_dir, library, existing_ids, result, progress_file=progress_file, on_added=on_added, password=password)


def add_password_required_archive(
    archive_path: Path,
    data_dir: Path,
    library: dict,
    existing_ids: set[str],
    result: dict,
    progress_file: Path | None = None,
    on_added=None,
) -> int:
    unique_key = f"archive-password:{normcase_path(archive_path)}"
    item_id = stable_id(unique_key)
    item = {
        "id": item_id,
        "name": archive_path.stem,
        "kind": "archive",
        "sourcePath": str(archive_path.resolve()),
        "comicPath": "",
        "internalPath": "",
        "cover": "",
        "categories": [],
        "pageCount": 0,
        "requiresPassword": True,
        "passwordKey": archive_password_key(archive_path),
        "addedAt": utc_now(),
    }
    if add_item(
        library=library,
        existing_ids=existing_ids,
        result=result,
        item=item,
        progress_file=progress_file,
        on_added=on_added,
        progress_type="needs_password",
        progress_message=f"需要密码：{archive_path.name}",
    ):
        return 1
    return 0


def add_paths(
    data_dir: Path,
    paths: list[str],
    protect_favorite: bool = False,
    include_library: bool = True,
    progress_file: Path | None = None,
) -> dict:
    data_dir.mkdir(parents=True, exist_ok=True)
    (data_dir / "covers").mkdir(parents=True, exist_ok=True)

    library = ensure_library(data_dir)
    existing_ids = {str(item.get("id")) for item in library.get("items", []) if item.get("id")}
    queued_for_title_recognition = []
    result = {
        "added": [],
        "skipped": [],
        "errors": [],
        "titleRecognition": {
            "queued": queued_for_title_recognition,
            "updated": [],
            "skipped": [],
            "errors": [],
        },
    }
    pending_save_count = 0
    last_incremental_save = time.monotonic()

    def save_library_incremental(force: bool = False) -> None:
        nonlocal pending_save_count, last_incremental_save
        pending_save_count += 1
        now = time.monotonic()
        if force or pending_save_count >= 20 or (now - last_incremental_save) >= 2.0:
            save_library(data_dir, library)
            pending_save_count = 0
            last_incremental_save = now

    def finalize_added_item(item: dict) -> None:
        item_id = str(item.get("id", ""))
        if protect_favorite and item_id:
            add_import_favorite_guard(data_dir, {item_id})

        remove_category_from_item(item, FAVORITE_CATEGORY)
        if not bool(item.get("requiresPassword", False)) and name_needs_title_recognition(item.get("name", "")):
            add_category_to_item(item, TITLE_RECOGNIZING_CATEGORY)
            queued_for_title_recognition.append(item_id)

        save_library_incremental()

    append_progress_event(progress_file, "start", f"开始批量添加：{len(paths)} 项", total=len(paths))

    for raw_path in paths:
        path = Path(raw_path).expanduser()
        append_progress_event(progress_file, "scan", f"扫描：{path}", path=str(path))
        try:
            if is_archive(path):
                existing_archive_name = existing_archive_source_name(library, path)
                if existing_archive_name is not None:
                    skipped = {"name": existing_archive_name, "path": str(path), "reason": "duplicate_source"}
                    result["skipped"].append(skipped)
                    append_progress_event(progress_file, "skipped", f"跳过已存在压缩包：{existing_archive_name}", **skipped)
                    continue

            if not path.exists():
                error = {"path": str(path), "message": "路径不存在。"}
                result["errors"].append(error)
                append_progress_event(progress_file, "error", f"路径不存在：{path}", path=str(path), errorMessage=error["message"])
                continue

            before_added = len(result["added"])
            before_skipped = len(result["skipped"])

            if path.is_dir():
                count = scan_folder(
                    path,
                    data_dir,
                    library,
                    existing_ids,
                    result,
                    progress_file=progress_file,
                    on_added=finalize_added_item,
                )
            elif path.is_file() and is_archive(path):
                try:
                    count = scan_archive(
                        path,
                        data_dir,
                        library,
                        existing_ids,
                        result,
                        progress_file=progress_file,
                        on_added=finalize_added_item,
                    )
                except ArchivePasswordRequiredError:
                    count = add_password_required_archive(
                        path,
                        data_dir,
                        library,
                        existing_ids,
                        result,
                        progress_file=progress_file,
                        on_added=finalize_added_item,
                    )
            else:
                skipped = {"path": str(path), "reason": "unsupported_file"}
                result["skipped"].append(skipped)
                append_progress_event(progress_file, "skipped", f"跳过非漫画文件：{path}", **skipped)
                continue

            if count == 0 and len(result["skipped"]) == before_skipped and len(result["added"]) == before_added:
                skipped = {"path": str(path), "reason": "no_images"}
                result["skipped"].append(skipped)
                append_progress_event(progress_file, "skipped", f"未找到图片，已跳过：{path}", **skipped)
        except Exception as exc:                                                       
            error = {"path": str(path), "message": str(exc)}
            result["errors"].append(error)
            append_progress_event(progress_file, "error", f"添加失败：{path}：{exc}", path=str(path), errorMessage=str(exc))

    save_library(data_dir, library)
    append_progress_event(
        progress_file,
        "done",
        f"批量添加完成：新增 {len(result['added'])} 本，跳过 {len(result['skipped'])} 项，错误 {len(result['errors'])} 项",
        added=len(result["added"]),
        skipped=len(result["skipped"]),
        errors=len(result["errors"]),
    )
    if include_library:
        result["library"] = library
    return result


def list_library(data_dir: Path) -> dict:
    library = ensure_library(data_dir)
    if ensure_item_page_counts(library):
        save_library(data_dir, library)
    return library


def add_category(data_dir: Path, name: str) -> dict:
    library = ensure_library(data_dir)
    category = ensure_category_exists(library, name)
    save_library(data_dir, library)
    return {"category": category, "library": library}


def rename_category(data_dir: Path, old_name: str, new_name: str) -> dict:
    old_category = normalize_category_name(old_name)
    new_category = normalize_category_name(new_name)
    if not old_category or not new_category:
        raise RuntimeError("分类名称不能为空。")
    if old_category in SYSTEM_CATEGORIES or new_category in SYSTEM_CATEGORIES:
        raise RuntimeError("系统分类不能重命名。")

    library = ensure_library(data_dir)
    categories = normalize_categories(library.get("categories", []), include_defaults=False)
    old_existing = next((value for value in categories if value.casefold() == old_category.casefold()), "")
    if not old_existing:
        raise RuntimeError("要重命名的分类不存在。")
    if any(value.casefold() == new_category.casefold() and value.casefold() != old_existing.casefold() for value in categories):
        raise RuntimeError("已存在同名分类。")

    library["categories"] = [new_category if value.casefold() == old_existing.casefold() else value for value in categories]
    for item in library.get("items", []):
        item_categories = normalize_categories(
            item.get("categories", []),
            include_defaults=False,
            allow_assignable_system=True,
        )
        item_categories = [value for value in item_categories if value not in MANAGED_TITLE_CATEGORIES]
        item["categories"] = [new_category if value.casefold() == old_existing.casefold() else value for value in item_categories]

    records = normalize_category_records(library.get("categoryRecords", []))
    for record in records:
        if str(record.get("name", "")).casefold() == old_existing.casefold():
            record["name"] = new_category
    library["categoryRecords"] = records

    aliases = normalize_category_aliases(library.get("categoryAliases", []))
    for alias in aliases:
        if alias["targetName"].casefold() == old_existing.casefold():
            alias["targetName"] = new_category
        if alias["sourceName"].casefold() == old_existing.casefold():
            alias["sourceName"] = new_category
    library["categoryAliases"] = normalize_category_aliases(aliases)

    save_library(data_dir, library)
    return {"oldCategory": old_existing, "category": new_category, "library": library}


def delete_category(data_dir: Path, name: str) -> dict:
    category = normalize_category_name(name)
    if not category:
        raise RuntimeError("分类名称不能为空。")
    if category in SYSTEM_CATEGORIES:
        raise RuntimeError("系统分类不能删除。")

    library = ensure_library(data_dir)
    before = normalize_categories(library.get("categories", []), include_defaults=False)
    library["categories"] = [value for value in before if value.casefold() != category.casefold()]
    removed = len(library["categories"]) != len(before)

    for item in library.get("items", []):
        item_categories = normalize_categories(
            item.get("categories", []),
            include_defaults=False,
            allow_assignable_system=True,
        )
        item_categories = [value for value in item_categories if value not in MANAGED_TITLE_CATEGORIES]
        item["categories"] = [value for value in item_categories if value.casefold() != category.casefold()]

    records = normalize_category_records(library.get("categoryRecords", []))
    library["categoryRecords"] = [record for record in records if str(record.get("name", "")).casefold() != category.casefold()]
    aliases = normalize_category_aliases(library.get("categoryAliases", []))
    library["categoryAliases"] = [
        alias
        for alias in aliases
        if alias["sourceName"].casefold() != category.casefold() and alias["targetName"].casefold() != category.casefold()
    ]
    save_library(data_dir, library)
    return {"category": category, "removed": removed, "library": library}


def clear_user_categories(data_dir: Path) -> dict:
    library = ensure_library(data_dir)
    removed_categories = normalize_categories(library.get("categories", []), include_defaults=False)
    removed_records = normalize_category_records(library.get("categoryRecords", []))
    removed_aliases = normalize_category_aliases(library.get("categoryAliases", []))

    removed_item_references = 0
    for item in library.get("items", []):
        if not isinstance(item, dict):
            continue
        item_categories = normalize_categories(
            item.get("categories", []),
            include_defaults=False,
            allow_assignable_system=True,
        )
        kept_categories: list[str] = []
        for category in item_categories:
            if category in ASSIGNABLE_SYSTEM_CATEGORIES:
                kept_categories.append(category)
            else:
                removed_item_references += 1
        item["categories"] = kept_categories

    library["categories"] = []
    library["categoryRecords"] = []
    library["categoryAliases"] = []
    save_library(data_dir, library)
    return {
        "removedCategories": len(removed_categories),
        "removedItemCategoryRefs": removed_item_references,
        "removedCategoryRecords": len(removed_records),
        "removedCategoryAliases": len(removed_aliases),
    }


def reset_tag_rules(data_dir: Path) -> dict:
    library = ensure_library(data_dir)
    records = normalize_category_records(library.get("categoryRecords", []))
    tag_record_names = {
        normalize_category_name(record.get("name", ""))
        for record in records
        if record.get("kind") == TAG_KIND
    }
    tag_record_names = {name for name in tag_record_names if name}
    tag_record_keys = {name.casefold() for name in tag_record_names}

    categories = normalize_categories(library.get("categories", []), include_defaults=False)
    kept_categories = [category for category in categories if category.casefold() not in tag_record_keys]

    removed_item_references = 0
    for item in library.get("items", []):
        if not isinstance(item, dict):
            continue
        item_categories = normalize_categories(
            item.get("categories", []),
            include_defaults=False,
            allow_assignable_system=True,
        )
        kept_item_categories: list[str] = []
        for category in item_categories:
            if category.casefold() in tag_record_keys:
                removed_item_references += 1
                continue
            kept_item_categories.append(category)
        item["categories"] = kept_item_categories

    translations = normalize_tag_translations(library.get("tagTranslations", {}))
    blacklist = normalize_tag_blacklist(library.get("tagBlacklist", []))
    aliases = normalize_category_aliases(library.get("categoryAliases", []))

    library["categories"] = kept_categories
    library["categoryRecords"] = [record for record in records if record.get("kind") != TAG_KIND]
    library["tagTranslations"] = {}
    library["tagBlacklist"] = []
    library["categoryAliases"] = []
    save_library(data_dir, library)
    return {
        "removedTagCategories": len(categories) - len(kept_categories),
        "removedItemCategoryRefs": removed_item_references,
        "removedTagRecords": len(records) - len(library["categoryRecords"]),
        "removedTagTranslations": len(translations),
        "removedTagBlacklist": len(blacklist),
        "removedCategoryAliases": len(aliases),
    }


def backup_library_file(data_dir: Path, reason: str) -> str:
    library_path = data_dir / "library.json"
    if not library_path.exists():
        return ""
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = data_dir / f"library.before-{reason}.{timestamp}.json"
    shutil.copy2(library_path, backup_path)
    return str(backup_path)


def tag_record_category_names(library: dict) -> set[str]:
    return {
        normalize_category_name(record.get("name", "")).casefold()
        for record in normalize_category_records(library.get("categoryRecords", []))
        if record.get("kind") == TAG_KIND and normalize_category_name(record.get("name", ""))
    }


def item_source_raw_tags(item: dict, source: str) -> list[str]:
    raw_tag_record = item.get("rawTags")
    if not isinstance(raw_tag_record, dict):
        return []
    if normalize_source_tag(source) != "wnacg":
        return []
    tags: list[str] = []
    seen: set[str] = set()
    for raw_tag in raw_tag_record.get("wnacg", []):
        tag = normalize_wnacg_tag(raw_tag)
        key = normalize_source_tag(tag)
        if tag and key not in seen:
            seen.add(key)
            tags.append(tag)
    return tags


def clear_source_raw_category_refs_from_item(library: dict, item: dict, source: str, *, clear_all_tag_records: bool = False) -> int:
    remove_keys: set[str] = set()
    raw_category_record = item.get("rawTagCategories")
    source_key = normalize_source_tag(source) or "wnacg"
    if isinstance(raw_category_record, dict):
        source_record = raw_category_record.get(source_key)
        if isinstance(source_record, dict):
            for value in source_record.values():
                for category in (value if isinstance(value, list) else [value]):
                    category_name = normalize_category_name(category)
                    if category_name:
                        remove_keys.add(category_name.casefold())

    if clear_all_tag_records:
        remove_keys.update(tag_record_category_names(library))

    if not remove_keys:
        return 0

    item_categories = normalize_categories(
        item.get("categories", []),
        include_defaults=False,
        allow_assignable_system=True,
    )
    kept: list[str] = []
    removed = 0
    for category in item_categories:
        if normalize_category_name(category).casefold() in remove_keys:
            removed += 1
            continue
        kept.append(category)
    item["categories"] = kept

    if isinstance(raw_category_record, dict):
        raw_category_record[source_key] = {}
        item["rawTagCategories"] = raw_category_record
    return removed


def reapply_raw_tag_rules(data_dir: Path, library: dict, source: str = "wnacg", raw_tags: list[str] | None = None) -> dict:
    source_key = normalize_source_tag(source) or "wnacg"
    target_tag_keys = {normalize_source_tag(tag) for tag in raw_tags or [] if normalize_source_tag(tag)}
    affected_items = []
    removed_refs = 0
    added_categories: set[str] = set()
    mapped_tags: set[str] = set()
    unmapped_tags: set[str] = set()
    blacklisted_tags: set[str] = set()

    for item in library.get("items", []):
        if not isinstance(item, dict):
            continue
        item_raw_tags = item_source_raw_tags(item, source_key)
        if not item_raw_tags:
            continue
        if target_tag_keys and not any(normalize_source_tag(tag) in target_tag_keys for tag in item_raw_tags):
            continue
        affected_items.append(item)

    for item in affected_items:
        removed_refs += clear_source_raw_category_refs_from_item(library, item, source_key)
        tag_match = item.get("tagMatch") if isinstance(item.get("tagMatch"), dict) else {}
        match = {
            "source": source_key,
            "query": tag_match.get("query", ""),
            "score": tag_match.get("score", 0),
            "url": tag_match.get("url", ""),
            "gallery": {
                "id": str(tag_match.get("id", "")),
                "title": str(tag_match.get("title", "") or item.get("name", "")),
                "filecount": str(tag_match.get("fileCount", "") or item.get("pageCount", "")),
                "tags": item_source_raw_tags(item, source_key),
            },
        }
        if source_key == "wnacg":
            tag_result = apply_wnacg_tags_to_item(data_dir, library, item, match)
        else:
            tag_result = {"categories": [], "targetTags": [], "unmappedTags": [], "blacklistedTags": []}
        added_categories.update(str(category) for category in tag_result.get("categories", []) if str(category))
        mapped_tags.update(str(tag) for tag in tag_result.get("targetTags", []) if str(tag))
        unmapped_tags.update(str(tag) for tag in tag_result.get("unmappedTags", []) if str(tag))
        blacklisted_tags.update(str(tag) for tag in tag_result.get("blacklistedTags", []) if str(tag))

    return {
        "affectedItems": len(affected_items),
        "removedItemCategoryRefs": removed_refs,
        "addedCategories": sorted(added_categories),
        "mappedTagCount": len(mapped_tags),
        "unmappedTagCount": len(unmapped_tags),
        "blacklistedTagCount": len(blacklisted_tags),
    }


def rebuild_wnacg_tag_categories(data_dir: Path, include_library: bool = True) -> dict:
    library = ensure_library(data_dir)
    backup_path = backup_library_file(data_dir, "wnacg-tag-rebuild")

    records = normalize_category_records(library.get("categoryRecords", []))
    old_wnacg_records = [
        record
        for record in records
        if record.get("kind") == TAG_KIND
        and (
            str(record.get("source", "")).casefold() == "wnacg"
            or str(record.get("sourceNamespace", "")).casefold() == "wnacg"
        )
    ]
    old_wnacg_names = {
        normalize_category_name(record.get("name", ""))
        for record in old_wnacg_records
        if normalize_category_name(record.get("name", ""))
    }

    kept_records = [
        record
        for record in records
        if record not in old_wnacg_records
    ]
    kept_record_names = {
        normalize_category_name(record.get("name", "")).casefold()
        for record in kept_records
        if normalize_category_name(record.get("name", ""))
    }
    removable_name_keys = {
        name.casefold()
        for name in old_wnacg_names
        if name.casefold() not in kept_record_names
    }

    categories = normalize_categories(library.get("categories", []), include_defaults=False)
    library["categories"] = [
        category
        for category in categories
        if category.casefold() not in removable_name_keys
    ]
    library["categoryRecords"] = kept_records

    aliases = normalize_category_aliases(library.get("categoryAliases", []))
    kept_aliases = [
        alias
        for alias in aliases
        if str(alias.get("sourceNamespace", "")).casefold() != "wnacg"
        and alias["sourceName"].casefold() not in removable_name_keys
        and alias["targetName"].casefold() not in removable_name_keys
    ]
    library["categoryAliases"] = kept_aliases

    removed_item_refs = 0
    for item in library.get("items", []):
        if not isinstance(item, dict):
            continue
        item_categories = normalize_categories(
            item.get("categories", []),
            include_defaults=False,
            allow_assignable_system=True,
        )
        next_categories: list[str] = []
        for category in item_categories:
            if category.casefold() in removable_name_keys:
                removed_item_refs += 1
                continue
            next_categories.append(category)
        item["categories"] = next_categories

    rebuilt_items = 0
    added_categories: set[str] = set()
    mapped_tags: set[str] = set()
    unmapped_tags: set[str] = set()
    raw_tag_count = 0
    for item in library.get("items", []):
        if not isinstance(item, dict):
            continue
        raw_tag_record = item.get("rawTags")
        if not isinstance(raw_tag_record, dict):
            continue
        raw_tags = [normalize_wnacg_tag(tag) for tag in raw_tag_record.get("wnacg", [])]
        raw_tags = [tag for tag in raw_tags if tag]
        if not raw_tags:
            continue

        removed_item_refs += clear_source_raw_category_refs_from_item(library, item, "wnacg", clear_all_tag_records=True)
        tag_match = item.get("tagMatch") if isinstance(item.get("tagMatch"), dict) else {}
        match = {
            "source": "wnacg",
            "query": tag_match.get("query", ""),
            "score": tag_match.get("score", 0),
            "url": tag_match.get("url", ""),
            "gallery": {
                "id": str(tag_match.get("id", "")),
                "title": str(tag_match.get("title", "") or item.get("name", "")),
                "filecount": str(tag_match.get("fileCount", "") or item.get("pageCount", "")),
                "tags": raw_tags,
            },
        }
        tag_result = apply_wnacg_tags_to_item(data_dir, library, item, match)
        rebuilt_items += 1
        raw_tag_count += int(tag_result.get("rawTagCount", 0) or 0)
        added_categories.update(str(category) for category in tag_result.get("categories", []) if str(category))
        mapped_tags.update(str(tag) for tag in tag_result.get("targetTags", []) if str(tag))
        unmapped_tags.update(str(tag) for tag in tag_result.get("unmappedTags", []) if str(tag))

    save_library(data_dir, library)
    result = {
        "backup": backup_path,
        "removedWnacgRecords": len(old_wnacg_records),
        "removedWnacgCategoryNames": len(removable_name_keys),
        "removedWnacgAliases": len(aliases) - len(kept_aliases),
        "removedItemCategoryRefs": removed_item_refs,
        "rebuiltItems": rebuilt_items,
        "rawTagCount": raw_tag_count,
        "mappedTagCount": len(mapped_tags),
        "unmappedTagCount": len(unmapped_tags),
        "addedCategories": sorted(added_categories),
        "unmappedTags": sorted(unmapped_tags),
    }
    if include_library:
        result["library"] = library
    return result


def tag_category_candidates(library: dict) -> list[dict]:
    candidates: list[dict] = []
    by_category: dict[str, dict] = {}
    for record in normalize_category_records(library.get("categoryRecords", [])):
        if record.get("kind") != TAG_KIND:
            continue
        namespace = str(record.get("sourceNamespace", "") or "")
        source_tag = str(record.get("sourceTag", "") or "")
        if namespace not in TAG_TARGET_NAMESPACES or not source_tag:
            continue
        category = resolve_tag_category_name(library, record.get("name", ""))
        if not category:
            continue
        category_key = category.casefold()
        entry = by_category.setdefault(
            category_key,
            {
                "category": category,
                "namespace": "",
                "tag": "",
                "targetKey": "",
                "targetKeys": [],
                "label": category,
            },
        )
        target_key = eh_tag_key(namespace, source_tag)
        if target_key not in entry["targetKeys"]:
            entry["targetKeys"].append(target_key)
        if not entry["targetKey"]:
            entry["namespace"] = namespace
            entry["tag"] = source_tag
            entry["targetKey"] = target_key

    candidates = list(by_category.values())
    return sorted(candidates, key=lambda value: natural_key(str(value.get("category", ""))))


def raw_mapping_target_summary(data_dir: Path, library: dict, mapping: dict | None, resolved: dict | None = None) -> dict:
    if mapping is not None:
        if mapping.get("targetKind") == "category":
            category = resolve_tag_category_name(library, mapping.get("targetCategory", ""))
            return {
                "targetKind": "category",
                "targetNamespace": "",
                "targetTag": "",
                "targetKey": "",
                "targetCategory": category,
            }
        namespace = str(mapping.get("targetNamespace", ""))
        tag = str(mapping.get("targetTag", ""))
        category = resolve_tag_category_name(library, translate_tag_display_name(data_dir, library, namespace, tag) or "")
        return {
            "targetKind": "eh",
            "targetNamespace": namespace,
            "targetTag": tag,
            "targetKey": eh_tag_key(namespace, tag),
            "targetCategory": category,
        }

    if resolved is not None:
        namespace = str(resolved.get("namespace", ""))
        tag = str(resolved.get("tag", ""))
        category = resolve_tag_category_name(library, translate_tag_display_name(data_dir, library, namespace, tag) or "")
        return {
            "targetKind": "eh",
            "targetNamespace": namespace,
            "targetTag": tag,
            "targetKey": eh_tag_key(namespace, tag),
            "targetCategory": category,
        }

    return {
        "targetKind": "",
        "targetNamespace": "",
        "targetTag": "",
        "targetKey": "",
        "targetCategory": "",
    }


def list_tag_mappings(data_dir: Path) -> dict:
    library = ensure_library(data_dir)
    source = "wnacg"
    raw_entries: dict[str, dict] = {}
    for item in library.get("items", []):
        if not isinstance(item, dict):
            continue
        item_name = str(item.get("name", "") or item.get("id", ""))
        item_id = str(item.get("id", ""))
        for tag in item_source_raw_tags(item, source):
            key = normalize_source_tag(tag)
            if not key:
                continue
            entry = raw_entries.setdefault(
                key,
                {
                    "source": source,
                    "rawTag": tag,
                    "sourceTag": key,
                    "itemIds": [],
                    "sampleItems": [],
                },
            )
            entry["itemIds"].append(item_id)
            if item_name and item_name not in entry["sampleItems"] and len(entry["sampleItems"]) < 3:
                entry["sampleItems"].append(item_name)

    for blacklist_key in normalize_tag_blacklist(library.get("tagBlacklist", [])):
        namespace, tag = split_eh_tag(blacklist_key)
        if namespace != source or not tag:
            continue
        raw_entries.setdefault(
            tag,
            {
                "source": source,
                "rawTag": tag,
                "sourceTag": tag,
                "itemIds": [],
                "sampleItems": [],
            },
        )

    library_reverse_index = build_library_ehtag_reverse_translation_index(library)
    db_reverse_index = load_ehtag_reverse_translation_index(data_dir)
    rows: list[dict] = []
    for entry in raw_entries.values():
        raw_tag = str(entry.get("rawTag", ""))
        mapping = find_raw_tag_mapping(library, source, raw_tag)
        blacklisted = is_raw_source_tag_blacklisted(library, source, raw_tag)
        resolved = None if mapping is not None or blacklisted else resolve_wnacg_tag_to_eh_tag(
            data_dir,
            library,
            raw_tag,
            library_reverse_index=library_reverse_index,
            db_reverse_index=db_reverse_index,
        )
        target = raw_mapping_target_summary(data_dir, library, mapping, resolved)
        if blacklisted:
            status = "blacklisted"
            statusText = "黑名单"
        elif mapping is not None:
            status = "manual"
            statusText = "手动映射" if mapping.get("targetKind") != "category" else "自定义分类"
        elif resolved is not None:
            status = "mapped"
            statusText = "已映射"
        else:
            status = "unmapped"
            statusText = "未映射"

        rows.append(
            {
                "source": source,
                "rawTag": raw_tag,
                "sourceTag": entry.get("sourceTag", ""),
                "status": status,
                "statusText": statusText,
                "itemCount": len(set(str(item_id) for item_id in entry.get("itemIds", []) if str(item_id))),
                "sampleItems": entry.get("sampleItems", []),
                **target,
            }
        )

    status_counts: dict[str, int] = {}
    for row in rows:
        status = str(row.get("status", ""))
        status_counts[status] = status_counts.get(status, 0) + 1

    return {
        "rows": sorted(rows, key=lambda value: (str(value.get("status", "")), natural_key(str(value.get("rawTag", ""))))),
        "targetCategories": tag_category_candidates(library),
        "statusCounts": status_counts,
    }


def find_category_record_by_name(library: dict, category: str) -> dict | None:
    category_key = normalize_category_name(category).casefold()
    if not category_key:
        return None
    for record in normalize_category_records(library.get("categoryRecords", [])):
        if normalize_category_name(record.get("name", "")).casefold() == category_key:
            return record
    return None


def map_raw_tag(data_dir: Path, source: str, raw_tag: str, target_category: str = "", target_namespace: str = "", target_tag: str = "", include_library: bool = True) -> dict:
    library = ensure_library(data_dir)
    source_key = normalize_source_tag(source) or "wnacg"
    raw = normalize_tag_display_name(raw_tag)
    if not raw:
        raise RuntimeError("原始 Tag 不能为空。")

    mapping: dict
    category = resolve_tag_category_name(library, target_category)
    if category:
        ensure_raw_category_exists(library, category)
        mapping = {
            "source": source_key,
            "rawTag": raw,
            "targetKind": "category",
            "targetCategory": category,
        }
    else:
        namespace = normalize_source_tag(target_namespace) or "other"
        tag = normalize_source_tag(target_tag)
        if namespace not in TAG_TARGET_NAMESPACES or not tag:
            raise RuntimeError("目标 EH Tag 无效。")
        mapping = {
            "source": source_key,
            "rawTag": raw,
            "targetKind": "eh",
            "targetNamespace": namespace,
            "targetTag": tag,
        }

    normalized = upsert_raw_tag_mapping(library, mapping)
    if normalized is None:
        raise RuntimeError("Tag 映射规则无效。")
    remove_raw_source_tag_from_blacklist(library, source_key, raw)
    reapply_result = reapply_raw_tag_rules(data_dir, library, source_key, [raw])
    save_library(data_dir, library)
    result = {
        "mapping": normalized,
        "reapplied": reapply_result,
    }
    if include_library:
        result["library"] = library
    return result


def blacklist_raw_tag(data_dir: Path, source: str, raw_tag: str, include_library: bool = True) -> dict:
    library = ensure_library(data_dir)
    source_key = normalize_source_tag(source) or "wnacg"
    raw = normalize_tag_display_name(raw_tag)
    if not raw:
        raise RuntimeError("原始 Tag 不能为空。")
    blacklist_key = add_raw_source_tag_to_blacklist(library, source_key, raw)
    removed_mapping = remove_raw_tag_mapping(library, source_key, raw)
    reapply_result = reapply_raw_tag_rules(data_dir, library, source_key, [raw])
    save_library(data_dir, library)
    result = {
        "blacklistKey": blacklist_key,
        "removedMapping": removed_mapping,
        "reapplied": reapply_result,
    }
    if include_library:
        result["library"] = library
    return result


def keep_raw_tag_as_category(data_dir: Path, source: str, raw_tag: str, category_name: str = "", include_library: bool = True) -> dict:
    raw = normalize_tag_display_name(raw_tag)
    category = normalize_category_name(category_name) or normalize_category_name(raw)
    if not raw or not category:
        raise RuntimeError("原始 Tag 不能为空。")
    return map_raw_tag(data_dir, source, raw, target_category=category, include_library=include_library)


def blacklist_category(data_dir: Path, name: str) -> dict:
    category = normalize_category_name(name)
    if not category:
        raise RuntimeError("分类名称不能为空。")
    if category in SYSTEM_CATEGORIES:
        raise RuntimeError("系统分类不能加入黑名单。")

    library = ensure_library(data_dir)
    records = normalize_category_records(library.get("categoryRecords", []))
    matched_records = [
        value
        for value in records
        if value.get("kind") == TAG_KIND and str(value.get("name", "")).casefold() == category.casefold()
    ]
    aliases = normalize_category_aliases(library.get("categoryAliases", []))
    matched_aliases = [
        value
        for value in aliases
        if value.get("sourceKind") == TAG_KIND
        and (
            str(value.get("sourceName", "")).casefold() == category.casefold()
            or str(value.get("targetName", "")).casefold() == category.casefold()
        )
    ]
    if not matched_records and not matched_aliases:
        raise RuntimeError("只有自动识别 Tag 生成的分类才能加入黑名单。")

    blacklist = normalize_tag_blacklist(library.get("tagBlacklist", []))
    added_tag_keys: list[str] = []
    for record in matched_records:
        namespace = str(record.get("sourceNamespace", "other") or "other")
        source_tag = str(record.get("sourceTag", "") or "")
        tag_key = eh_tag_key(namespace, source_tag)
        if tag_key not in blacklist:
            blacklist.append(tag_key)
            added_tag_keys.append(tag_key)
    for alias in matched_aliases:
        namespace = str(alias.get("sourceNamespace", "other") or "other")
        source_tag = str(alias.get("sourceTag", "") or "")
        tag_key = eh_tag_key(namespace, source_tag)
        if tag_key not in blacklist:
            blacklist.append(tag_key)
            added_tag_keys.append(tag_key)
    library["tagBlacklist"] = blacklist
    library["categoryRecords"] = records

    prune_disallowed_tag_categories(library)
    save_library(data_dir, library)
    return {
        "category": category,
        "tagKeys": added_tag_keys,
        "library": library,
    }


def merge_categories(data_dir: Path, source_name: str, target_name: str) -> dict:
    source = normalize_category_name(source_name)
    target = normalize_category_name(target_name)
    if not source or not target:
        raise RuntimeError("分类名称不能为空。")
    if source in SYSTEM_CATEGORIES or target in SYSTEM_CATEGORIES:
        raise RuntimeError("系统分类不能合并。")
    if source.casefold() == target.casefold():
        raise RuntimeError("不能把分类合并到自身。")

    library = ensure_library(data_dir)
    categories = normalize_categories(library.get("categories", []), include_defaults=False)
    source_existing = next((value for value in categories if value.casefold() == source.casefold()), "")
    target_existing = next((value for value in categories if value.casefold() == target.casefold()), "")
    if not source_existing:
        raise RuntimeError("要合并的源分类不存在。")
    if not target_existing:
        raise RuntimeError("目标分类不存在。")

    aliases = normalize_category_aliases(library.get("categoryAliases", []))
    for alias in aliases:
        if alias["targetName"].casefold() == source_existing.casefold():
            alias["targetName"] = target_existing
    library["categoryAliases"] = aliases

    records = normalize_category_records(library.get("categoryRecords", []))
    source_record = next(
        (
            record
            for record in records
            if str(record.get("name", "")).casefold() == source_existing.casefold()
        ),
        None,
    )
    alias = {
        "sourceName": source_existing,
        "targetName": target_existing,
        "sourceKind": MANUAL_CATEGORY_KIND,
    }
    if source_record is not None and source_record.get("kind") == TAG_KIND:
        alias.update(
            {
                "sourceKind": TAG_KIND,
                "sourceNamespace": str(source_record.get("sourceNamespace", "other")),
                "sourceTag": str(source_record.get("sourceTag", "")),
            }
        )
    add_category_alias(library, alias)
    apply_category_aliases(library)
    save_library(data_dir, library)
    return {
        "sourceCategory": source_existing,
        "targetCategory": target_existing,
        "library": library,
    }


def update_item_category(
    data_dir: Path,
    item_ids: list[str],
    category: str,
    action: str,
    explicit_favorite: bool = False,
    include_library: bool = True,
) -> dict:
    library = ensure_library(data_dir)
    category = ensure_assignable_category_exists(library, category)
    id_set = {str(item_id) for item_id in item_ids}
    updated: list[str] = []
    guarded: list[str] = []
    blocked: list[str] = []
    is_favorite_add = category == FAVORITE_CATEGORY and action == "add"
    is_managed_title_category_add = (
        category in (ASSIGNABLE_SYSTEM_CATEGORIES - USER_ASSIGNABLE_SYSTEM_CATEGORIES)
        and action == "add"
    )
    favorite_guard = load_import_favorite_guard(data_dir) if is_favorite_add and not explicit_favorite else set()

    for item in library.get("items", []):
        item_id = str(item.get("id", ""))
        if item_id not in id_set:
            continue

        if is_managed_title_category_add:
            blocked.append(item_id)
            continue

        if is_favorite_add and not explicit_favorite:
            if item_id in favorite_guard:
                guarded.append(item_id)
            else:
                blocked.append(item_id)
            continue

        item_categories = normalize_categories(
            item.get("categories", []),
            include_defaults=False,
            allow_assignable_system=True,
        )
        item_categories = [value for value in item_categories if value not in MANAGED_TITLE_CATEGORIES]
        has_category = any(value.casefold() == category.casefold() for value in item_categories)

        if action == "add" and not has_category:
            item_categories.append(category)
            updated.append(item_id)
            if category not in ASSIGNABLE_SYSTEM_CATEGORIES:
                set_tag_status(item, TAG_STATUS_NONE)
        elif action == "remove" and has_category:
            item_categories = [value for value in item_categories if value.casefold() != category.casefold()]
            updated.append(item_id)
        elif action not in {"add", "remove"}:
            raise RuntimeError("未知分类操作。")

        item["categories"] = item_categories

    save_library(data_dir, library)
    result = {
        "category": category,
        "action": action,
        "updated": updated,
        "guarded": guarded,
        "blocked": blocked,
    }
    if include_library:
        result["library"] = library
    return result


def strip_html_tags(value: str) -> str:
    return re.sub(r"<[^>]+>", " ", value)


def html_unescape_text(value: object) -> str:
    return unescape(str(value or "")).strip()


def html_attr(attrs_text: str, name: str) -> str:
    pattern = re.compile(
        rf"\b{re.escape(name)}\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))",
        flags=re.IGNORECASE,
    )
    match = pattern.search(str(attrs_text or ""))
    if not match:
        return ""
    return html_unescape_text(next((group for group in match.groups() if group is not None), ""))


def compact_query_text(value: str) -> str:
    text = str(value or "")
    text = re.sub(r"\.[a-z0-9]{2,5}$", "", text, flags=re.IGNORECASE)
    text = re.sub(r"[_]+", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip(" \t\r\n-_.")


def parse_title_search_seeds(title: str) -> dict:
    raw_title = compact_query_text(title)
    working = raw_title
    extracted = {
        "raw": raw_title,
        "circle": "",
        "artist": "",
        "title": "",
        "event": "",
        "translator": "",
        "parody": "",
        "seeds": [],
    }

    leading_match = re.match(r"^\s*\[([^\[\]]+)\]\s*(.+)$", working)
    if leading_match:
        circle_part = leading_match.group(1).strip()
        working = leading_match.group(2).strip()
        author_match = re.match(r"(.+?)\s*[\(（]([^\(\)（）]+)[\)）]\s*$", circle_part)
        if author_match:
            extracted["circle"] = compact_query_text(author_match.group(1))
            extracted["artist"] = compact_query_text(author_match.group(2))
        else:
            extracted["circle"] = compact_query_text(circle_part)

    trailing_groups: list[str] = []
    while True:
        trailing_match = re.search(r"\s*[\[【]([^\[】\]]+)[\]】]\s*$", working)
        if not trailing_match:
            break
        trailing_groups.append(compact_query_text(trailing_match.group(1)))
        working = working[: trailing_match.start()].strip()
    if trailing_groups:
        extracted["translator"] = next((group for group in trailing_groups if group), "")

    event_match = re.search(r"[\(（]([Cc]\d{2,3}|COMIC1[^（）()]*|[^（）()]*例大祭[^（）()]*)[\)）]\s*$", working)
    if event_match:
        extracted["event"] = compact_query_text(event_match.group(1))
        working = working[: event_match.start()].strip()

    for source, normalized in KNOWN_PARODY_SEEDS.items():
        if source.casefold() in raw_title.casefold():
            extracted["parody"] = normalized
            break

    extracted["title"] = compact_query_text(working) or raw_title

    seeds: list[str] = []

    def add_seed(*parts: str) -> None:
        seed = compact_query_text(" ".join(part for part in parts if part))
        if not seed:
            return
        key = normalize_title_key(seed)
        if key and all(normalize_title_key(existing) != key for existing in seeds):
            seeds.append(seed)

    add_seed(extracted["title"], extracted["artist"])
    add_seed(extracted["title"], extracted["circle"])
    add_seed(extracted["title"], extracted["parody"])
    add_seed(extracted["title"])
    add_seed(raw_title)
    extracted["seeds"] = seeds[:5]
    return extracted


def build_wnacg_search_query(parsed_title: dict) -> str:
    title = compact_query_text(str(parsed_title.get("title", "") or parsed_title.get("raw", "") or ""))
    title = re.sub(r"\s*[\[【][^\]】]+[\]】]", " ", title)
    title = compact_query_text(title)
    if not title:
        seeds = list(parsed_title.get("seeds", []))
        return str(seeds[0]) if seeds else ""

    parts = [
        compact_query_text(part.strip(" \t\r\n-_.－—―"))
        for part in re.split(r"\s*[-－—―]\s*|[|｜]", title)
    ]
    parts = [part for part in parts if len(normalize_title_key(part)) >= 3]
    return parts[0] if parts else title


def similarity_score(left: str, right: str) -> float:
    left_key = normalize_title_key(left)
    right_key = normalize_title_key(right)
    if not left_key or not right_key:
        return 0.0
    if left_key == right_key:
        return 1.0
    if left_key in right_key or right_key in left_key:
        return 0.86

    left_tokens = {token for token in re.split(r"[^0-9a-zA-Z\u3040-\u30ff\u3400-\u9fff]+", left.casefold()) if token}
    right_tokens = {token for token in re.split(r"[^0-9a-zA-Z\u3040-\u30ff\u3400-\u9fff]+", right.casefold()) if token}
    if not left_tokens or not right_tokens:
        return 0.0
    overlap = len(left_tokens & right_tokens)
    union = len(left_tokens | right_tokens)
    return overlap / union if union else 0.0


def eh_cookie_header(data_dir: Path) -> str:
    env_cookie = os.environ.get("MANGASHELF_EH_COOKIE", "").strip()
    if env_cookie:
        return env_cookie
    cookie_file = data_dir / "eh-cookies.txt"
    if cookie_file.exists():
        return " ".join(line.strip() for line in cookie_file.read_text(encoding="utf-8").splitlines() if line.strip() and not line.strip().startswith("#"))
    return ""


def eh_base_url() -> str:
    return os.environ.get("MANGASHELF_EH_BASE_URL", EH_DEFAULT_BASE_URL).strip().rstrip("/") or EH_DEFAULT_BASE_URL


def normalize_tag_delay_range(min_delay_ms: int, max_delay_ms: int) -> tuple[int, int]:
    minimum = max(TAG_SCRAPE_MIN_DELAY_MS, int(min_delay_ms or TAG_SCRAPE_MIN_DELAY_MS))
    maximum = max(minimum, int(max_delay_ms or TAG_SCRAPE_MAX_DELAY_MS))
    return minimum, maximum


class TagRequestDelay:
    def __init__(self, min_delay_ms: int, max_delay_ms: int, progress_callback=None) -> None:
        self.min_delay_ms, self.max_delay_ms = normalize_tag_delay_range(min_delay_ms, max_delay_ms)
        self.progress_callback = progress_callback
        self.requested_sites: set[str] = set()

    def before_request(self, site: str = "default") -> None:
        site_key = str(site or "default").casefold()
        site_label = str(site or "请求")
        if site_key in self.requested_sites:
            delay_ms = random.randint(self.min_delay_ms, self.max_delay_ms)
            if self.progress_callback:
                self.progress_callback(
                    "tag_wait",
                    f"{site_label} 等待 {delay_ms / 1000:.1f} 秒后继续请求",
                    delayMs=delay_ms,
                    site=site_label,
                )
            time.sleep(delay_ms / 1000)
        self.requested_sites.add(site_key)


def eh_request(data_dir: Path, url: str, *, data: bytes | None = None, content_type: str = "") -> bytes:
    headers = {
        "User-Agent": "mangaga/0.1 (+local personal manga manager)",
        "Accept": "application/json,text/html;q=0.9,*/*;q=0.8",
    }
    cookie = eh_cookie_header(data_dir)
    if cookie:
        headers["Cookie"] = cookie
    if content_type:
        headers["Content-Type"] = content_type
    request = urllib.request.Request(url, data=data, headers=headers, method="POST" if data is not None else "GET")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"EH 请求失败：HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"EH 请求失败：{exc.reason}") from exc


def parse_gallery_links(html_text: str) -> list[dict]:
    results: list[dict] = []
    seen: set[tuple[int, str]] = set()
    pattern = re.compile(
        r"<a\b[^>]*href=[\"'](?P<href>(?:https?://(?:e-|ex)hentai\.org)?/g/(?P<gid>\d+)/(?P<token>[0-9a-fA-F]+)/?)[\"'][^>]*>(?P<label>.*?)</a>",
        flags=re.IGNORECASE | re.DOTALL,
    )
    for match in pattern.finditer(html_text):
        gid = int(match.group("gid"))
        token = match.group("token")
        key = (gid, token)
        if key in seen:
            continue
        seen.add(key)
        title = compact_query_text(unescape(strip_html_tags(match.group("label"))))
        results.append(
            {
                "gid": gid,
                "token": token,
                "url": f"{eh_base_url()}/g/{gid}/{token}/",
                "title": title,
            }
        )
        if len(results) >= TAG_SEARCH_RESULT_LIMIT:
            break
    return results


def search_eh_galleries(data_dir: Path, query: str, before_request=None) -> list[dict]:
    params = urllib.parse.urlencode({"f_search": query})
    url = f"{eh_base_url()}/?{params}"
    if before_request:
        before_request()
    payload = eh_request(data_dir, url).decode("utf-8", errors="replace")
    return parse_gallery_links(payload)


def eh_gdata(data_dir: Path, gallery_refs: list[dict], before_request=None) -> list[dict]:
    if not gallery_refs:
        return []
    gidlist = [[int(ref["gid"]), str(ref["token"])] for ref in gallery_refs[:25]]
    payload = json.dumps({"method": "gdata", "gidlist": gidlist, "namespace": 1}).encode("utf-8")
    if before_request:
        before_request()
    response = eh_request(data_dir, EH_API_URL, data=payload, content_type="application/json").decode("utf-8", errors="replace")
    data = json.loads(response)
    metadata = data.get("gmetadata", [])
    if not isinstance(metadata, list):
        return []
    return [entry for entry in metadata if isinstance(entry, dict) and not entry.get("error")]


def wnacg_base_url() -> str:
    return os.environ.get("MANGASHELF_WNACG_BASE_URL", WNACG_DEFAULT_BASE_URL).strip().rstrip("/") or WNACG_DEFAULT_BASE_URL


def wnacg_request(data_dir: Path, url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "mangaga/0.1 (+local personal manga manager)",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,ja;q=0.7,en;q=0.5",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=WNACG_REQUEST_TIMEOUT_SECONDS) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"WNACG 请求失败：HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"WNACG 请求失败：{exc.reason}") from exc


def absolute_site_url(base_url: str, href: str) -> str:
    return urllib.parse.urljoin(f"{base_url.rstrip('/')}/", str(href or ""))


def decode_wnacg_html(payload: bytes) -> str:
    for encoding in ("utf-8", "big5", "gb18030"):
        try:
            return payload.decode(encoding)
        except UnicodeDecodeError:
            continue
    return payload.decode("utf-8", errors="replace")


def normalize_wnacg_tag(value: object) -> str:
    tag = normalize_tag_display_name(strip_html_tags(html_unescape_text(value)))
    tag = tag.strip(" #,，;；:：")
    if not tag or len(tag) > 50:
        return ""
    if tag.casefold() in {"tag", "tags", "标签", "標籤", "更多", "全部"}:
        return ""
    return tag


def extract_wnacg_page_count(text: str) -> int:
    value = strip_html_tags(html_unescape_text(text))
    patterns = (
        r"(?:頁數|页数|页數|頁数|Pages?)\s*[:：]?\s*(\d{1,5})",
        r"(\d{1,5})\s*(?:張|张)\s*(?:圖片|图片|照片)",
        r"(\d{1,5})\s*(?:P|p|頁|页)",
    )
    for pattern in patterns:
        match = re.search(pattern, value, flags=re.IGNORECASE)
        if not match:
            continue
        try:
            return int(match.group(1))
        except ValueError:
            return 0
    return 0


def clean_wnacg_title(value: object) -> str:
    title = compact_query_text(strip_html_tags(html_unescape_text(value)))
    title = re.sub(r"\s*[-_]\s*(?:紳士漫畫|绅士漫画|WNACG).*$", "", title, flags=re.IGNORECASE)
    return title.strip()


def parse_wnacg_search_results(html_text: str) -> list[dict]:
    base_url = wnacg_base_url()
    results: list[dict] = []
    result_indexes: dict[str, int] = {}
    anchor_pattern = re.compile(
        r"<a\b(?P<attrs>(?:\"[^\"]*\"|'[^']*'|[^'\">])*)>(?P<label>.*?)</a>",
        flags=re.IGNORECASE | re.DOTALL,
    )

    for match in anchor_pattern.finditer(html_text):
        attrs = match.group("attrs")
        href = html_attr(attrs, "href")
        aid_match = re.search(r"photos-index-(?:page-\d+-)?aid-(?P<id>\d+)\.html", href, flags=re.IGNORECASE)
        if not aid_match:
            continue
        gallery_id = aid_match.group("id")
        label_title = clean_wnacg_title(match.group("label"))
        title = clean_wnacg_title(html_attr(attrs, "title")) or label_title
        if not title:
            continue

        start = max(0, match.start() - 900)
        end = min(len(html_text), match.end() + 900)
        page_count = extract_wnacg_page_count(html_text[start:end])
        url = absolute_site_url(base_url, href)

        if gallery_id in result_indexes:
            existing = results[result_indexes[gallery_id]]
            if len(title) > len(str(existing.get("title", ""))):
                existing["title"] = title
            if page_count and not int(existing.get("filecount", 0) or 0):
                existing["filecount"] = page_count
            continue

        result_indexes[gallery_id] = len(results)
        results.append(
            {
                "id": gallery_id,
                "url": url,
                "title": title,
                "filecount": page_count,
            }
        )
        if len(results) >= TAG_SEARCH_RESULT_LIMIT:
            break
    return results


def parse_wnacg_detail(html_text: str) -> dict:
    title = ""
    for pattern in (
        r"<h1\b[^>]*>(?P<title>.*?)</h1>",
        r"<h2\b[^>]*>(?P<title>.*?)</h2>",
        r"<title\b[^>]*>(?P<title>.*?)</title>",
    ):
        match = re.search(pattern, html_text, flags=re.IGNORECASE | re.DOTALL)
        if match:
            title = clean_wnacg_title(match.group("title"))
            if title:
                break

    tags: list[str] = []
    seen_tags: set[str] = set()
    anchor_pattern = re.compile(r"<a\b(?P<attrs>[^>]*)>(?P<label>.*?)</a>", flags=re.IGNORECASE | re.DOTALL)
    for match in anchor_pattern.finditer(html_text):
        attrs = match.group("attrs")
        css_class = html_attr(attrs, "class")
        if "tagshow" not in css_class.casefold():
            continue
        tag = normalize_wnacg_tag(match.group("label"))
        if not tag:
            continue
        key = tag.casefold()
        if key in seen_tags:
            continue
        seen_tags.add(key)
        tags.append(tag)

    return {
        "title": title,
        "tags": tags,
        "filecount": extract_wnacg_page_count(html_text),
    }


def search_wnacg_galleries(data_dir: Path, query: str, before_request=None) -> list[dict]:
    params = urllib.parse.urlencode({"q": query, "syn": "yes", "f": "_all", "s": "create_time_DESC"})
    url = f"{wnacg_base_url()}/search/index.php?{params}"
    if before_request:
        before_request()
    payload = decode_wnacg_html(wnacg_request(data_dir, url))
    return parse_wnacg_search_results(payload)


def fetch_wnacg_detail(data_dir: Path, candidate: dict, before_request=None) -> dict:
    url = str(candidate.get("url", ""))
    if not url:
        return {"title": "", "tags": [], "filecount": 0}
    if before_request:
        before_request()
    payload = decode_wnacg_html(wnacg_request(data_dir, url))
    detail = parse_wnacg_detail(payload)
    detail["url"] = url
    detail["id"] = str(candidate.get("id", ""))
    if not detail.get("title"):
        detail["title"] = str(candidate.get("title", ""))
    if not int(detail.get("filecount", 0) or 0):
        detail["filecount"] = int(candidate.get("filecount", 0) or 0)
    return detail


def score_gallery_match(item: dict, parsed_title: dict, query: str, metadata: dict) -> float:
    item_name = str(item.get("name", ""))
    title = str(metadata.get("title", "") or "")
    title_jpn = str(metadata.get("title_jpn", "") or "")
    score = max(similarity_score(item_name, title), similarity_score(item_name, title_jpn)) * 70
    score += max(similarity_score(parsed_title.get("title", ""), title), similarity_score(parsed_title.get("title", ""), title_jpn)) * 35
    score += similarity_score(query, title) * 12

    page_count = int(item.get("pageCount", 0) or 0)
    try:
        file_count = int(str(metadata.get("filecount", "0") or "0"))
    except ValueError:
        file_count = 0
    if page_count > 0 and file_count > 0:
        diff_ratio = abs(page_count - file_count) / max(page_count, file_count)
        score += max(0, 18 * (1 - diff_ratio))

    tags = [str(tag) for tag in metadata.get("tags", []) if isinstance(tag, str)]
    tag_text = " ".join(tags)
    for key in ("artist", "circle", "parody"):
        value = str(parsed_title.get(key, "") or "")
        if value and value.casefold() in tag_text.casefold():
            score += 12
    return round(score, 2)


def score_wnacg_match(item: dict, parsed_title: dict, query: str, candidate: dict, detail: dict | None = None) -> float:
    metadata = detail or candidate
    item_name = str(item.get("name", ""))
    title = str(metadata.get("title", "") or candidate.get("title", "") or "")
    score = similarity_score(item_name, title) * 70
    score += similarity_score(parsed_title.get("title", ""), title) * 35
    score += similarity_score(query, title) * 12

    page_count = int(item.get("pageCount", 0) or 0)
    try:
        file_count = int(metadata.get("filecount", 0) or 0)
    except (TypeError, ValueError):
        file_count = 0
    if page_count > 0 and file_count > 0:
        diff_ratio = abs(page_count - file_count) / max(page_count, file_count)
        score += max(0, 18 * (1 - diff_ratio))

    tag_text = " ".join(str(tag) for tag in metadata.get("tags", []) if isinstance(tag, str))
    for key in ("artist", "circle", "parody"):
        value = str(parsed_title.get(key, "") or "")
        if value and (value.casefold() in title.casefold() or value.casefold() in tag_text.casefold()):
            score += 12
    return round(score, 2)


def find_best_eh_match(data_dir: Path, item: dict, progress_callback=None, before_request=None) -> dict | None:
    parsed = parse_title_search_seeds(str(item.get("name", "")))
    seeds = list(parsed.get("seeds", []))
    query = seeds[0] if seeds else compact_query_text(str(item.get("name", "")))
    if not query:
        return None
    best: dict | None = None

    if progress_callback:
        progress_callback("tag_search", f"搜索 EH：{query}", query=query, source="exhentai")
    galleries = search_eh_galleries(data_dir, query, before_request=before_request)
    if progress_callback:
        progress_callback("tag_metadata", f"读取 EH 元数据：{len(galleries)} 个候选", query=query, candidateCount=len(galleries), source="exhentai")
    metadata = eh_gdata(data_dir, galleries, before_request=before_request)
    by_key = {(int(entry.get("gid", 0) or 0), str(entry.get("token", ""))): entry for entry in metadata}
    for gallery in galleries:
        entry = by_key.get((int(gallery["gid"]), str(gallery["token"])))
        if entry is None:
            continue
        score = score_gallery_match(item, parsed, query, entry)
        candidate = {
            "source": "exhentai",
            "query": query,
            "score": score,
            "gallery": entry,
            "url": gallery.get("url", ""),
            "parsedTitle": parsed,
        }
        if best is None or score > best["score"]:
            best = candidate
            if progress_callback:
                progress_callback("tag_match", f"EH 当前最佳匹配：{score} 分", query=query, score=score, source="exhentai")

    if best is not None and best["score"] >= TAG_MATCH_MIN_SCORE:
        return best
    if progress_callback:
        if best is None:
            progress_callback("tag_no_match", f"EH 未找到候选：{query}", query=query, source="exhentai")
        else:
            progress_callback(
                "tag_no_match",
                f"EH 最高 {best['score']} 分，未达 {TAG_MATCH_MIN_SCORE} 分",
                query=query,
                score=best["score"],
                source="exhentai",
            )
    return None


def find_best_wnacg_match(data_dir: Path, item: dict, progress_callback=None, before_request=None) -> dict | None:
    parsed = parse_title_search_seeds(str(item.get("name", "")))
    query = build_wnacg_search_query(parsed) or compact_query_text(str(item.get("name", "")))
    if not query:
        return None

    if progress_callback:
        progress_callback("tag_search", f"搜索 WNACG：{query}", query=query, source="wnacg")
    candidates = search_wnacg_galleries(data_dir, query, before_request=before_request)
    if not candidates:
        if progress_callback:
            progress_callback("tag_no_match", f"WNACG 未找到候选：{query}", query=query, source="wnacg")
        return None

    scored_candidates = [
        {
            "candidate": candidate,
            "score": score_wnacg_match(item, parsed, query, candidate),
        }
        for candidate in candidates
    ]
    best_search = max(scored_candidates, key=lambda value: value["score"])
    best_candidate = best_search["candidate"]
    if progress_callback:
        progress_callback(
            "tag_metadata",
            f"读取 WNACG 详情：{best_candidate.get('title', '')}",
            query=query,
            candidateCount=len(candidates),
            score=best_search["score"],
            source="wnacg",
        )

    detail = fetch_wnacg_detail(data_dir, best_candidate, before_request=before_request)
    score = score_wnacg_match(item, parsed, query, best_candidate, detail)
    tags = [tag for tag in detail.get("tags", []) if normalize_wnacg_tag(tag)]
    if score < TAG_MATCH_MIN_SCORE or not tags:
        if progress_callback:
            if not tags:
                progress_callback("tag_no_match", "WNACG 命中候选但未读取到 tag", query=query, score=score, source="wnacg")
            else:
                progress_callback(
                    "tag_no_match",
                    f"WNACG 最高 {score} 分，未达 {TAG_MATCH_MIN_SCORE} 分",
                    query=query,
                    score=score,
                    source="wnacg",
                )
        return None

    if progress_callback:
        progress_callback("tag_match", f"WNACG 当前最佳匹配：{score} 分", query=query, score=score, source="wnacg")
    return {
        "source": "wnacg",
        "query": query,
        "score": score,
        "gallery": {
            "id": str(detail.get("id", "") or best_candidate.get("id", "")),
            "title": str(detail.get("title", "") or best_candidate.get("title", "")),
            "filecount": int(detail.get("filecount", 0) or best_candidate.get("filecount", 0) or 0),
            "tags": tags,
        },
        "url": str(detail.get("url", "") or best_candidate.get("url", "")),
        "parsedTitle": parsed,
    }


def apply_eh_tags_to_item(data_dir: Path, library: dict, item: dict, match: dict) -> dict:
    gallery = match.get("gallery", {})
    raw_tags = [str(tag) for tag in gallery.get("tags", []) if isinstance(tag, str)]
    added_categories: list[str] = []
    target_tags: list[str] = []
    untranslated_tags: list[str] = []

    for raw_tag in raw_tags:
        namespace, tag = split_eh_tag(raw_tag)
        if not tag:
            continue
        if namespace not in TAG_TARGET_NAMESPACES:
            continue
        target_tags.append(eh_tag_key(namespace, tag))
        category_name = ensure_tag_category(data_dir, library, namespace, tag)
        if category_name is None:
            untranslated_tags.append(eh_tag_key(namespace, tag))
            continue
        add_category_to_item(item, category_name)
        if category_name not in added_categories:
            added_categories.append(category_name)

    item["tagClassifiedAt"] = utc_now()
    set_tag_status(item, TAG_STATUS_NONE)
    item["tagMatch"] = {
        "source": "exhentai",
        "query": match.get("query", ""),
        "score": match.get("score", 0),
        "gid": str(gallery.get("gid", "")),
        "token": str(gallery.get("token", "")),
        "url": match.get("url", ""),
        "title": str(gallery.get("title", "") or ""),
        "titleJpn": str(gallery.get("title_jpn", "") or ""),
        "fileCount": str(gallery.get("filecount", "") or ""),
        "matchedAt": utc_now(),
    }
    item.pop("tagLastError", None)
    return {
        "categories": added_categories,
        "targetTags": target_tags,
        "untranslatedTags": untranslated_tags,
    }


def apply_wnacg_tags_to_item(data_dir: Path, library: dict, item: dict, match: dict) -> dict:
    gallery = match.get("gallery", {})
    raw_tags: list[str] = []
    seen_raw_tags: set[str] = set()
    for raw_tag in gallery.get("tags", []):
        tag = normalize_wnacg_tag(raw_tag)
        tag_key = normalize_tag_alias_key(tag) or tag.casefold()
        if not tag or tag_key in seen_raw_tags:
            continue
        seen_raw_tags.add(tag_key)
        raw_tags.append(tag)

    raw_tag_record = item.get("rawTags")
    if not isinstance(raw_tag_record, dict):
        raw_tag_record = {}
    raw_tag_record["wnacg"] = raw_tags
    item["rawTags"] = raw_tag_record

    added_categories: list[str] = []
    target_tags: list[str] = []
    seen_target_tags: set[str] = set()
    untranslated_tags: list[str] = []
    unmapped_tags: list[str] = []
    blacklisted_tags: list[str] = []
    raw_tag_categories: dict[str, list[str]] = {}
    library_reverse_index = build_library_ehtag_reverse_translation_index(library)
    db_reverse_index = load_ehtag_reverse_translation_index(data_dir)

    for tag in raw_tags:
        if is_raw_source_tag_blacklisted(library, "wnacg", tag):
            blacklisted_tags.append(tag)
            continue

        mapping = find_raw_tag_mapping(library, "wnacg", tag)
        target_key = ""
        category_name = None
        if mapping is not None and mapping.get("targetKind") == "category":
            target_category = resolve_tag_category_name(library, mapping.get("targetCategory", ""))
            if target_category:
                category_name = ensure_raw_category_exists(library, target_category)
                target_key = source_raw_tag_key("wnacg", tag)
        else:
            if mapping is not None:
                resolved = {
                    "namespace": str(mapping.get("targetNamespace", "")),
                    "tag": str(mapping.get("targetTag", "")),
                }
            else:
                resolved = resolve_wnacg_tag_to_eh_tag(
                    data_dir,
                    library,
                    tag,
                    library_reverse_index=library_reverse_index,
                    db_reverse_index=db_reverse_index,
                )

            if resolved is None:
                unmapped_tags.append(tag)
                continue

            namespace = resolved["namespace"]
            tag_key = resolved["tag"]
            target_key = eh_tag_key(namespace, tag_key)
            category_name = ensure_tag_category(data_dir, library, namespace, tag_key)

        if target_key and target_key not in seen_target_tags:
            seen_target_tags.add(target_key)
            target_tags.append(target_key)
        if category_name is None:
            if target_key and target_key not in untranslated_tags:
                untranslated_tags.append(target_key)
            continue
        add_category_to_item(item, category_name)
        raw_tag_categories[tag] = [category_name]
        if category_name not in added_categories:
            added_categories.append(category_name)

    item_raw_category_record = item.get("rawTagCategories")
    if not isinstance(item_raw_category_record, dict):
        item_raw_category_record = {}
    item_raw_category_record["wnacg"] = raw_tag_categories
    item["rawTagCategories"] = item_raw_category_record

    item["tagClassifiedAt"] = utc_now()
    set_tag_status(item, TAG_STATUS_NONE)
    item["tagMatch"] = {
        "source": "wnacg",
        "query": match.get("query", ""),
        "score": match.get("score", 0),
        "id": str(gallery.get("id", "")),
        "url": match.get("url", ""),
        "title": str(gallery.get("title", "") or ""),
        "fileCount": str(gallery.get("filecount", "") or ""),
        "rawTagCount": len(raw_tags),
        "mappedTagCount": len(target_tags),
        "unmappedTagCount": len(unmapped_tags),
        "blacklistedTagCount": len(blacklisted_tags),
        "matchedAt": utc_now(),
    }
    item.pop("tagLastError", None)
    return {
        "categories": added_categories,
        "targetTags": target_tags,
        "untranslatedTags": untranslated_tags,
        "unmappedTags": unmapped_tags,
        "blacklistedTags": blacklisted_tags,
        "rawTagCount": len(raw_tags),
    }


def classify_tags(
    data_dir: Path,
    item_ids: list[str],
    delay_ms: int = TAG_SCRAPE_MIN_DELAY_MS,
    delay_max_ms: int = TAG_SCRAPE_MAX_DELAY_MS,
    progress_file: Path | None = None,
    include_library: bool = True,
) -> dict:
    library = ensure_library(data_dir)
    targets = {str(item_id) for item_id in item_ids if str(item_id)}
    delay_min_ms, delay_max_ms = normalize_tag_delay_range(delay_ms, delay_max_ms)
    result = {
        "updated": [],
        "skipped": [],
        "notFound": [],
        "errors": [],
        "delayMinMs": delay_min_ms,
        "delayMaxMs": delay_max_ms,
        "concurrency": 1,
        "library": library,
    }
    target_items = [item for item in library.get("items", []) if isinstance(item, dict) and (not targets or str(item.get("id", "")) in targets)]
    total = len(target_items)

    append_progress_event(
        progress_file,
        "tag_start",
        f"开始 Tag 识别：{total} 本，随机请求间隔 {delay_min_ms / 1000:.1f}-{delay_max_ms / 1000:.1f} 秒",
        total=total,
        delayMinMs=delay_min_ms,
        delayMaxMs=delay_max_ms,
        concurrency=1,
    )

    delay_controller: TagRequestDelay | None = None
    for index, item in enumerate(target_items):
        item_id = str(item.get("id", ""))
        item_name = str(item.get("name", "") or item_id)
        progress_base = {
            "id": item_id,
            "name": item_name,
            "index": index + 1,
            "total": total,
        }

        def report_tag_progress(event_type: str, message: str, **fields: object) -> None:
            payload = dict(progress_base)
            payload.update(fields)
            append_progress_event(progress_file, event_type, message, **payload)

        if delay_controller is None:
            delay_controller = TagRequestDelay(delay_min_ms, delay_max_ms, progress_callback=report_tag_progress)
        else:
            delay_controller.progress_callback = report_tag_progress

        try:
            report_tag_progress("tag_item", f"Tag识别：{index + 1}/{total} {item_name}")
            if get_title_status(item) == TITLE_STATUS_RECOGNIZING:
                result["skipped"].append({"id": item_id, "reason": "title_recognizing"})
                report_tag_progress("tag_skipped", f"跳过：{item_name} 仍在识别作品名", reason="title_recognizing")
                continue
            if get_title_status(item) == TITLE_STATUS_PENDING and not bool(item.get("titleSelected", False)):
                result["skipped"].append({"id": item_id, "reason": "title_not_selected"})
                report_tag_progress("tag_skipped", f"跳过：{item_name} 尚未选择作品名", reason="title_not_selected")
                continue
            before_eh_request = lambda: delay_controller.before_request("EH")
            before_wnacg_request = lambda: delay_controller.before_request("WNACG")
            match = find_best_eh_match(
                data_dir,
                item,
                progress_callback=report_tag_progress,
                before_request=before_eh_request,
            )
            if match is None:
                report_tag_progress("tag_fallback", f"EH 未匹配，改搜 WNACG：{item_name}", source="wnacg")
                match = find_best_wnacg_match(
                    data_dir,
                    item,
                    progress_callback=report_tag_progress,
                    before_request=before_wnacg_request,
                )
            if match is None:
                set_tag_status(item, TAG_STATUS_NOT_FOUND)
                item["tagLastError"] = "未找到 EH/WNACG 搜索结果。"
                result["notFound"].append({"id": item_id, "name": item_name, "message": item["tagLastError"]})
                report_tag_progress("tag_not_found", f"Tag未找到：{item_name}", errorMessage=item["tagLastError"])
                continue
            if match.get("source") == "wnacg":
                tag_result = apply_wnacg_tags_to_item(data_dir, library, item, match)
            else:
                tag_result = apply_eh_tags_to_item(data_dir, library, item, match)
            categories = list(tag_result.get("categories", []))
            untranslated_tags = list(tag_result.get("untranslatedTags", []))
            unmapped_tags = list(tag_result.get("unmappedTags", []))
            blacklisted_tags = list(tag_result.get("blacklistedTags", []))
            result["updated"].append(
                {
                    "id": item_id,
                    "name": item.get("name", ""),
                    "categoryCount": len(categories),
                    "targetTagCount": len(tag_result.get("targetTags", [])),
                    "untranslatedTagCount": len(untranslated_tags),
                    "untranslatedTags": untranslated_tags,
                    "unmappedTagCount": len(unmapped_tags),
                    "unmappedTags": unmapped_tags,
                    "blacklistedTagCount": len(blacklisted_tags),
                    "blacklistedTags": blacklisted_tags,
                    "rawTagCount": int(tag_result.get("rawTagCount", 0) or 0),
                    "score": match.get("score", 0),
                    "query": match.get("query", ""),
                    "source": match.get("source", "exhentai"),
                }
            )
            category_text = "、".join(categories) if categories else "无新分类"
            if untranslated_tags:
                category_text += f"；未翻译 {len(untranslated_tags)} 个"
            if unmapped_tags:
                category_text += f"；未映射 {len(unmapped_tags)} 个"
            if blacklisted_tags:
                category_text += f"；黑名单 {len(blacklisted_tags)} 个"
            report_tag_progress(
                "tag_updated",
                f"已分类：{item_name} -> {category_text}",
                categoryCount=len(categories),
                untranslatedTagCount=len(untranslated_tags),
                unmappedTagCount=len(unmapped_tags),
                blacklistedTagCount=len(blacklisted_tags),
                rawTagCount=int(tag_result.get("rawTagCount", 0) or 0),
                score=match.get("score", 0),
                query=match.get("query", ""),
                source=match.get("source", "exhentai"),
            )
        except Exception as exc:                                                           
            item["tagLastError"] = str(exc) or "Tag 识别失败。"
            result["errors"].append({"id": item_id, "message": item["tagLastError"]})
            report_tag_progress("tag_error", f"Tag识别失败：{item_name}：{item['tagLastError']}", errorMessage=item["tagLastError"])

    save_library(data_dir, library)
    append_progress_event(
        progress_file,
        "tag_done",
        f"Tag识别完成：成功 {len(result['updated'])} 本，未找到 {len(result['notFound'])} 本，跳过 {len(result['skipped'])} 本，错误 {len(result['errors'])} 本",
        updated=len(result["updated"]),
        notFound=len(result["notFound"]),
        skipped=len(result["skipped"]),
        errors=len(result["errors"]),
    )
    if include_library:
        result["library"] = library
    else:
        result.pop("library", None)
    return result


def recognize_titles(data_dir: Path, item_ids: list[str], progress_callback=None) -> dict:
    library = ensure_library(data_dir)
    targets = item_ids or [str(item.get("id", "")) for item in library.get("items", [])]
    result = recognize_titles_for_items(data_dir, library, targets, progress_callback=progress_callback)
    save_library(data_dir, library)
    result["library"] = library
    return result


def write_worker_progress(progress_file: Path, payload: dict) -> None:
    progress_file.parent.mkdir(parents=True, exist_ok=True)
    temp_path = temp_json_path(progress_file)
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    replace_file_with_retry(temp_path, progress_file)


def title_recognition_worker(data_dir: Path, item_ids: list[str], progress_file: Path, pause_file: Path) -> dict:
    total = len(item_ids)
    completed = 0

    progress = {
        "status": "starting",
        "total": total,
        "completed": completed,
        "currentId": "",
        "currentName": "",
        "itemProgress": 0,
        "itemTotal": 0,
        "message": "",
    }
    write_worker_progress(progress_file, progress)

    for item_id in item_ids:
        if pause_file.exists():
            progress.update({"status": "paused", "itemProgress": 0, "itemTotal": 0, "message": "已暂停。"})
            write_worker_progress(progress_file, progress)
            return progress

        try:
            item = get_library_item(data_dir, item_id)
            current_name = str(item.get("name", ""))
        except Exception:
            current_name = item_id

        progress.update(
            {
                "status": "running",
                "completed": completed,
                "currentId": item_id,
                "currentName": current_name,
                "itemProgress": 0,
                "itemTotal": 0,
                "message": "",
            }
        )
        write_worker_progress(progress_file, progress)

        def report_item_progress(item_progress: int, item_total: int, message: str) -> None:
            progress.update(
                {
                    "status": "running",
                    "completed": completed,
                    "currentId": item_id,
                    "currentName": current_name,
                    "itemProgress": max(0, item_progress),
                    "itemTotal": max(0, item_total),
                    "message": message,
                }
            )
            write_worker_progress(progress_file, progress)

        try:
            report_item_progress(0, 0, "检查作品名")
            result = recognize_titles(data_dir, [item_id], progress_callback=report_item_progress)
        except Exception as exc:                                                      
            message = str(exc) or "作品名识别失败。"
            progress.update(
                {
                    "status": "error",
                    "completed": completed,
                    "currentId": item_id,
                    "currentName": current_name,
                    "itemProgress": 0,
                    "itemTotal": 0,
                    "message": message,
                }
            )
            write_worker_progress(progress_file, progress)
            return progress

        errors = [error for error in result.get("errors", []) if isinstance(error, dict)]
        if errors:
            message = str(errors[0].get("message", "") or "作品名识别失败。")
            progress.update(
                {
                    "status": "error",
                    "completed": completed,
                    "currentId": item_id,
                    "currentName": current_name,
                    "itemProgress": 0,
                    "itemTotal": 0,
                    "message": message,
                }
            )
            write_worker_progress(progress_file, progress)
            return progress

        completed += 1
        progress.update(
            {
                "status": "completed",
                "completed": completed,
                "currentId": item_id,
                "currentName": current_name,
                "itemProgress": 0,
                "itemTotal": 0,
                "message": "",
            }
        )
        write_worker_progress(progress_file, progress)

    progress.update(
        {
            "status": "done",
            "completed": completed,
            "currentId": "",
            "currentName": "",
            "itemProgress": 0,
            "itemTotal": 0,
            "message": "识别完成。",
        }
    )
    write_worker_progress(progress_file, progress)
    return progress


def select_title_candidate(data_dir: Path, item_id: str, name: str) -> dict:
    clean_name = normalize_title_candidate_name(name)
    if not clean_name:
        raise RuntimeError("作品名不能为空。")

    library = ensure_library(data_dir)
    selected_item: dict | None = None
    for item in library.get("items", []):
        if str(item.get("id", "")) == str(item_id):
            selected_item = item
            break

    if selected_item is None:
        raise RuntimeError("书架中找不到该漫画。")

    candidates = normalize_title_candidates(selected_item.get("titleCandidates", []))
    candidate_names = [candidate["name"] for candidate in candidates]
    if candidate_names:
        matched = next((value for value in candidate_names if normalize_title_key(value) == normalize_title_key(clean_name)), "")
        if not matched:
            raise RuntimeError("选择的作品名不在候选列表中。")
        clean_name = matched

    selected_item["titleCandidates"] = candidates
    selected_item["name"] = clean_name
    selected_item["titleSelected"] = True
    selected_item["titleSelectedAt"] = utc_now()

    save_library(data_dir, library)
    return {
        "id": item_id,
        "name": clean_name,
        "titleSelected": True,
        "library": library,
    }


def get_library_item(data_dir: Path, item_id: str) -> dict:
    library = ensure_library(data_dir)
    for item in library.get("items", []):
        if str(item.get("id")) == item_id:
            return item
    raise RuntimeError("书架中找不到该漫画。")


def remove_items(data_dir: Path, item_ids: list[str]) -> dict:
    library = ensure_library(data_dir)
    id_set = {str(item_id).strip() for item_id in item_ids if str(item_id).strip()}
    kept_items = []
    removed = []
    cleanup_errors = []
    cover_cleanup_paths: list[tuple[str, Path]] = []
    cover_cleanup_keys: set[str] = set()

    for item in library.get("items", []):
        item_id = str(item.get("id", "")).strip()
        if item_id not in id_set:
            kept_items.append(item)
            continue

        removed.append({"id": item_id, "name": item.get("name", "")})

        cover_path = safe_data_child(data_dir, item.get("cover", ""))
        if cover_path and cover_path.exists():
            cover_cleanup_paths.append((item_id, cover_path))
            cover_cleanup_keys.add(str(cover_path))

    removed_ids = {item["id"] for item in removed}
    missing = sorted(id_set.difference(removed_ids))
    library["items"] = kept_items

    progress = ensure_progress(data_dir)
    for item_id in id_set:
        progress.get("items", {}).pop(item_id, None)

    save_library(data_dir, library)
    save_progress_file(data_dir, progress)

    for item_id in id_set:
        fallback_cover = safe_data_child(data_dir, Path("covers") / f"{item_id}.png")
        if fallback_cover and fallback_cover.exists() and str(fallback_cover) not in cover_cleanup_keys:
            cover_cleanup_paths.append((item_id, fallback_cover))
            cover_cleanup_keys.add(str(fallback_cover))

    for item_id, cover_path in cover_cleanup_paths:
        try:
            if cover_path.exists():
                cover_path.unlink()
        except Exception as exc:
            cleanup_errors.append({"id": item_id, "path": str(cover_path), "message": str(exc)})

    for item_id in id_set:
        page_cache = safe_data_child(data_dir, Path("page-cache") / item_id)
        try:
            if page_cache and page_cache.exists():
                shutil.rmtree(page_cache)
        except Exception as exc:
            cleanup_errors.append({"id": item_id, "path": str(page_cache), "message": str(exc)})

    session_root = safe_data_child(data_dir, "session-cache")
    if session_root and session_root.exists() and id_set:
        try:
            session_dirs = list(session_root.iterdir())
        except Exception as exc:
            cleanup_errors.append({"id": "", "path": str(session_root), "message": str(exc)})
            session_dirs = []
        for session_dir in session_dirs:
            try:
                if not session_dir.is_dir():
                    continue
                for item_id in id_set:
                    session_item_cache = session_dir / item_id
                    if session_item_cache.exists() and session_item_cache.is_dir():
                        shutil.rmtree(session_item_cache)
            except Exception as exc:
                cleanup_errors.append({"id": "", "path": str(session_dir), "message": str(exc)})

    return {
        "removed": removed,
        "missing": missing,
        "cleanupErrors": cleanup_errors,
        "library": library,
    }


def folder_pages(item: dict) -> list[dict]:
    comic_path = Path(str(item.get("comicPath", "")))
    if not comic_path.exists() or not comic_path.is_dir():
        raise RuntimeError("原始文件夹不存在或无法访问。")

    pages = [
        {
            "kind": "folder",
            "path": str(path),
            "displayPath": path.name,
        }
        for path in comic_path.iterdir()
        if path.is_file() and is_image(path)
    ]
    pages.sort(key=lambda page: natural_key(Path(page["path"]).name))
    return pages


def archive_pages(item: dict, password: str | None = None) -> list[dict]:
    archive_path = Path(str(item.get("sourcePath", "")))
    internal_dir = normalize_internal_path(str(item.get("internalPath", "")))

    if not archive_path.exists() or not archive_path.is_file():
        raise RuntimeError("原始压缩包不存在或无法访问。")

    if bool(item.get("requiresPassword", False)) and password is None:
        raise ArchivePasswordRequiredError(f"需要密码：{archive_path.name}")

    if archive_path.suffix.casefold() == ".zip":
        with zipfile.ZipFile(archive_path) as archive:
            members = [info.filename for info in archive.infolist() if not info.is_dir()]
    else:
        reader = get_external_reader()
        if reader is None:
            raise RuntimeError("未找到 7z/7zz/7za 或 7-Zip 默认安装路径，无法读取 rar 或 7z。")
        members = reader.list_files(archive_path, password=password)

    grouped = grouped_archive_images(members)
    if internal_dir not in grouped and bool(item.get("requiresPassword", False)) and grouped:
        internal_dir = sorted(grouped, key=natural_key)[0]
        item["internalPath"] = normalize_internal_path(internal_dir)

    images = grouped.get(internal_dir, [])
    item["pageCount"] = len(images)
    return [
        {
            "kind": "archive",
            "member": original,
            "displayPath": normalized,
        }
        for normalized, original in images
    ]


def item_pages(item: dict, password: str | None = None) -> list[dict]:
    if item.get("kind") == "folder":
        return folder_pages(item)
    if item.get("kind") == "archive":
        return archive_pages(item, password=password)
    raise RuntimeError("未知漫画类型。")


def page_info(data_dir: Path, item_id: str) -> dict:
    item = get_library_item(data_dir, item_id)
    pages = item_pages(item)
    progress = ensure_progress(data_dir).get("items", {}).get(item_id, {})
    page_index = int(progress.get("pageIndex", 0) or 0)
    if pages:
        page_index = max(0, min(page_index, len(pages) - 1))
    else:
        page_index = 0

    return {
        "id": item_id,
        "name": item.get("name", ""),
        "pageCount": len(pages),
        "progressIndex": page_index,
        "pages": [
            {
                "index": index,
                "displayPath": page["displayPath"],
            }
            for index, page in enumerate(pages)
        ],
    }


def direct_view_path_for_folder_page(
    *,
    data_dir: Path,
    session_id: str,
    item_id: str,
    index: int,
    page: dict,
    cache: bool = True,
) -> str:
    source_path = Path(page["path"])
    suffix = source_path.suffix.casefold()
    if suffix in WPF_DIRECT_IMAGE_EXTS:
        return str(source_path)

    cache_path = session_item_dir(data_dir, session_id, item_id) / f"{index:05d}{READER_CONVERTED_IMAGE_EXT}"
    if cache and not cache_path.exists():
        save_reader_image_from_file(source_path, cache_path)
    return str(cache_path)


def write_archive_reader_page(
    *,
    data_dir: Path,
    session_id: str,
    item_id: str,
    index: int,
    page: dict,
    image_bytes: bytes,
) -> str:
    suffix = Path(page["displayPath"]).suffix.casefold()
    if suffix in WPF_DIRECT_IMAGE_EXTS:
        cache_path = session_item_dir(data_dir, session_id, item_id) / f"{index:05d}{suffix}"
        if not cache_path.exists():
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            cache_path.write_bytes(image_bytes)
        return str(cache_path)

    cache_path = session_item_dir(data_dir, session_id, item_id) / f"{index:05d}{READER_CONVERTED_IMAGE_EXT}"
    if not cache_path.exists():
        save_reader_image_from_bytes(image_bytes, cache_path)
    return str(cache_path)


def archive_reader_cache_path(data_dir: Path, session_id: str, item_id: str, index: int, page: dict) -> Path:
    suffix = Path(page["displayPath"]).suffix.casefold()
    if suffix in WPF_DIRECT_IMAGE_EXTS:
        return session_item_dir(data_dir, session_id, item_id) / f"{index:05d}{suffix}"
    return session_item_dir(data_dir, session_id, item_id) / f"{index:05d}{READER_CONVERTED_IMAGE_EXT}"


def cache_index_set(page_count: int, start_index: int = 0, count: int = READER_INITIAL_CACHE_COUNT) -> set[int]:
    if page_count <= 0 or count <= 0:
        return set()
    start = max(0, min(start_index, page_count - 1))
    total = min(page_count, count)
    return {(start + offset) % page_count for offset in range(total)}


def page_reader_direct_suffix(page: dict) -> str:
    return Path(str(page.get("displayPath") or page.get("path") or "")).suffix.casefold()


def page_requires_reader_conversion(page: dict) -> bool:
    suffix = page_reader_direct_suffix(page)
    return suffix not in WPF_DIRECT_IMAGE_EXTS


def initial_reader_cache_indexes(pages: list[dict], page_index: int, requested_count: int) -> set[int]:
    if not pages:
        return set()

    requested_count = max(1, requested_count)
    indexes = cache_index_set(len(pages), page_index, requested_count)
    if requested_count > 1 and any(page_requires_reader_conversion(pages[index]) for index in indexes):
        return cache_index_set(len(pages), page_index, 1)
    return indexes


def prepare_folder_reader_pages(data_dir: Path, session_id: str, item_id: str, pages: list[dict], cache_indexes: set[int] | None = None) -> list[dict]:
    cache_indexes = cache_indexes or set()
    prepared = []
    for index, page in enumerate(pages):
        prepared.append(
            {
                "index": index,
                "displayPath": page["displayPath"],
                "viewPath": direct_view_path_for_folder_page(
                    data_dir=data_dir,
                    session_id=session_id,
                    item_id=item_id,
                    index=index,
                    page=page,
                    cache=index in cache_indexes,
                ),
            }
        )
    return prepared


def prepare_zip_reader_pages(
    data_dir: Path,
    session_id: str,
    item_id: str,
    archive_path: Path,
    pages: list[dict],
    password: str | None = None,
    cache_indexes: set[int] | None = None,
) -> list[dict]:
    cache_indexes = cache_indexes or set()
    prepared = []
    with zipfile.ZipFile(archive_path) as archive:
        for index, page in enumerate(pages):
            cache_path = archive_reader_cache_path(data_dir, session_id, item_id, index, page)
            if cache_path.exists() or index not in cache_indexes:
                view_path = str(cache_path)
            else:
                view_path = write_archive_reader_page(
                    data_dir=data_dir,
                    session_id=session_id,
                    item_id=item_id,
                    index=index,
                    page=page,
                    image_bytes=read_zip_member(archive, page["member"], password),
                )
            prepared.append({"index": index, "displayPath": page["displayPath"], "viewPath": view_path})
    return prepared


def prepare_external_archive_reader_pages(
    data_dir: Path,
    session_id: str,
    item_id: str,
    archive_path: Path,
    pages: list[dict],
    password: str | None = None,
    cache_indexes: set[int] | None = None,
) -> list[dict]:
    cache_indexes = cache_indexes or set()
    reader = get_external_reader()
    if reader is None:
        raise RuntimeError("未找到 7z/7zz/7za 或 7-Zip 默认安装路径，无法读取 rar 或 7z。")

    prepared = []
    for index, page in enumerate(pages):
        cache_path = archive_reader_cache_path(data_dir, session_id, item_id, index, page)
        if cache_path.exists() or index not in cache_indexes:
            view_path = str(cache_path)
        else:
            view_path = write_archive_reader_page(
                data_dir=data_dir,
                session_id=session_id,
                item_id=item_id,
                index=index,
                page=page,
                image_bytes=reader.read_file(archive_path, page["member"], password=password),
            )
        prepared.append({"index": index, "displayPath": page["displayPath"], "viewPath": view_path})
    return prepared


def needs_password_response(item: dict, message: str = "") -> dict:
    archive_path = Path(str(item.get("sourcePath", "")))
    return {
        "id": item.get("id", ""),
        "name": item.get("name", archive_path.stem),
        "needsPassword": True,
        "message": message or f"需要密码：{archive_path.name}",
    }


def prepare_reader(
    data_dir: Path,
    item_id: str,
    session_id: str,
    password: str | None = None,
    initial_count: int = READER_INITIAL_CACHE_COUNT,
) -> dict:
    library = ensure_library(data_dir)
    item = None
    for candidate in library.get("items", []):
        if str(candidate.get("id")) == item_id:
            item = candidate
            break
    if item is None:
        raise RuntimeError("书架中找不到该漫画。")

    archive_path = Path(str(item.get("sourcePath", ""))) if item.get("kind") == "archive" else None
    effective_password = None
    if item.get("kind") == "archive":
        effective_password = get_archive_password(data_dir, archive_path, password)
        if bool(item.get("requiresPassword", False)) and effective_password is None:
            return needs_password_response(item)

    try:
        pages = item_pages(item, password=effective_password)
    except ArchivePasswordRequiredError as exc:
        return needs_password_response(item, str(exc))
    except ArchivePasswordIncorrectError as exc:
        return needs_password_response(item, str(exc))

    progress = ensure_progress(data_dir).get("items", {}).get(item_id, {})
    page_index = int(progress.get("pageIndex", 0) or 0)
    if pages:
        page_index = max(0, min(page_index, len(pages) - 1))
    else:
        page_index = 0
    initial_cache_indexes = initial_reader_cache_indexes(pages, page_index, initial_count)

    if item.get("kind") == "folder":
        prepared_pages = prepare_folder_reader_pages(data_dir, session_id, item_id, pages, cache_indexes=initial_cache_indexes)
    elif item.get("kind") == "archive":
        try:
            if archive_path.suffix.casefold() == ".zip":
                prepared_pages = prepare_zip_reader_pages(data_dir, session_id, item_id, archive_path, pages, password=effective_password, cache_indexes=initial_cache_indexes)
            else:
                prepared_pages = prepare_external_archive_reader_pages(data_dir, session_id, item_id, archive_path, pages, password=effective_password, cache_indexes=initial_cache_indexes)
        except ArchivePasswordRequiredError as exc:
            return needs_password_response(item, str(exc))
        except ArchivePasswordIncorrectError as exc:
            return needs_password_response(item, str(exc))
    else:
        raise RuntimeError("未知漫画类型。")

    unlocked_password_item = item.get("kind") == "archive" and effective_password is not None and bool(item.get("requiresPassword", False))
    if item.get("kind") == "archive" and effective_password is not None:
        if password is not None:
            save_archive_password(data_dir, archive_path, password)
        item["requiresPassword"] = False
        item["pageCount"] = len(pages)
        if not item.get("cover") and prepared_pages:
            cover_rel = Path("covers") / f"{item_id}.png"
            cover_path = data_dir / cover_rel
            save_cover_from_file(Path(prepared_pages[0]["viewPath"]), cover_path)
            item["cover"] = cover_rel.as_posix()
        normalize_item_password_fields(item)
        save_library(data_dir, library)

    return {
        "id": item_id,
        "name": item.get("name", ""),
        "pageCount": len(prepared_pages),
        "progressIndex": page_index,
        "sessionId": clean_path_segment(session_id),
        "unlockedPasswordItem": unlocked_password_item,
        "pages": prepared_pages,
    }


def prepare_reader_window(
    data_dir: Path,
    item_id: str,
    session_id: str,
    start_index: int,
    count: int = READER_INITIAL_CACHE_COUNT,
    password: str | None = None,
) -> dict:
    item = get_library_item(data_dir, item_id)
    archive_path = Path(str(item.get("sourcePath", ""))) if item.get("kind") == "archive" else None
    effective_password = None
    if item.get("kind") == "archive":
        effective_password = get_archive_password(data_dir, archive_path, password)
        if bool(item.get("requiresPassword", False)) and effective_password is None:
            return needs_password_response(item)

    try:
        pages = item_pages(item, password=effective_password)
    except ArchivePasswordRequiredError as exc:
        return needs_password_response(item, str(exc))
    except ArchivePasswordIncorrectError as exc:
        return needs_password_response(item, str(exc))

    if not pages:
        return {"id": item_id, "pageCount": 0, "cached": []}

    normalized_start = max(0, min(start_index, len(pages) - 1))
    indexes = cache_index_set(len(pages), normalized_start, count)
    if item.get("kind") == "folder":
        prepared_pages = prepare_folder_reader_pages(data_dir, session_id, item_id, pages, cache_indexes=indexes)
    elif item.get("kind") == "archive":
        if archive_path.suffix.casefold() == ".zip":
            prepared_pages = prepare_zip_reader_pages(data_dir, session_id, item_id, archive_path, pages, password=effective_password, cache_indexes=indexes)
        else:
            prepared_pages = prepare_external_archive_reader_pages(data_dir, session_id, item_id, archive_path, pages, password=effective_password, cache_indexes=indexes)
    else:
        raise RuntimeError("未知漫画类型。")

    cached = [prepared_pages[index] for index in sorted(indexes) if 0 <= index < len(prepared_pages)]
    return {
        "id": item_id,
        "pageCount": len(prepared_pages),
        "startIndex": normalized_start,
        "count": len(cached),
        "cached": cached,
    }


def prepare_reader_page(data_dir: Path, item_id: str, session_id: str, page_index: int, password: str | None = None) -> dict:
    result = prepare_reader_window(
        data_dir=data_dir,
        item_id=item_id,
        session_id=session_id,
        start_index=page_index,
        count=1,
        password=password,
    )
    if result.get("needsPassword"):
        return result
    cached = result.get("cached", [])
    if not cached:
        raise RuntimeError("页码超出范围。")
    return {
        "id": item_id,
        "pageIndex": page_index,
        "pageCount": result.get("pageCount", 0),
        "page": cached[0],
    }


def export_page(data_dir: Path, item_id: str, page_index: int) -> dict:
    item = get_library_item(data_dir, item_id)
    pages = item_pages(item)
    if not pages:
        raise RuntimeError("该漫画没有可阅读的图片。")
    if page_index < 0 or page_index >= len(pages):
        raise RuntimeError("页码超出范围。")

    cache_rel = Path("page-cache") / item_id / f"{page_index:05d}.png"
    cache_path = safe_data_child(data_dir, cache_rel)
    if cache_path is None:
        raise RuntimeError("页缓存路径无效。")

    page = pages[page_index]
    if item.get("kind") == "folder":
        save_reader_image_from_file(Path(page["path"]), cache_path)
    elif item.get("kind") == "archive":
        archive_path = Path(str(item.get("sourcePath", "")))
        if archive_path.suffix.casefold() == ".zip":
            with zipfile.ZipFile(archive_path) as archive:
                with archive.open(page["member"]) as handle:
                    save_reader_image_from_bytes(handle.read(), cache_path)
        else:
            reader = get_external_reader()
            if reader is None:
                raise RuntimeError("未找到 7z/7zz/7za 或 7-Zip 默认安装路径，无法读取 rar 或 7z。")
            save_reader_image_from_bytes(reader.read_file(archive_path, page["member"]), cache_path)
    else:
        raise RuntimeError("未知漫画类型。")

    return {
        "id": item_id,
        "name": item.get("name", ""),
        "pageIndex": page_index,
        "pageCount": len(pages),
        "pagePath": str(cache_path),
        "displayPath": page["displayPath"],
    }


def save_reading_progress(data_dir: Path, item_id: str, page_index: int) -> dict:
    get_library_item(data_dir, item_id)
    progress = ensure_progress(data_dir)
    progress["items"][item_id] = {
        "pageIndex": max(0, page_index),
        "updatedAt": utc_now(),
    }
    save_progress_file(data_dir, progress)
    return {"id": item_id, "pageIndex": max(0, page_index)}


def file_digest(path: Path, algorithm: str = "sha256") -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(4 * 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def resolve_item_cover_path(data_dir: Path, item: dict) -> Path | None:
    cover = str(item.get("cover", "") or "").strip()
    if not cover:
        return None

    cover_path = Path(cover)
    if not cover_path.is_absolute():
        cover_path = safe_data_child(data_dir, cover)
        if cover_path is None:
            return None

    if not cover_path.exists() or not cover_path.is_file():
        return None
    return cover_path


def perceptual_hash_image(image: Image.Image, hash_size: int = 8, highfreq_factor: int = 2) -> str:
    size = hash_size * highfreq_factor
    grayscale = ImageOps.exif_transpose(image).convert("L").resize((size, size), Image.Resampling.LANCZOS)
    pixel_data = grayscale.get_flattened_data() if hasattr(grayscale, "get_flattened_data") else grayscale.getdata()
    pixels = [float(value) for value in pixel_data]
    coeffs: list[float] = []

    for v in range(hash_size):
        for u in range(hash_size):
            total = 0.0
            for y in range(size):
                y_factor = math.cos(((2 * y + 1) * v * math.pi) / (2 * size))
                row_offset = y * size
                for x in range(size):
                    x_factor = math.cos(((2 * x + 1) * u * math.pi) / (2 * size))
                    total += pixels[row_offset + x] * x_factor * y_factor
            coeffs.append(total)

    comparable = sorted(coeffs[1:])
    median = comparable[len(comparable) // 2] if comparable else 0.0
    bits = "".join("1" if value > median else "0" for value in coeffs)
    return f"{int(bits, 2):016x}"


def cover_phash(data_dir: Path, item: dict) -> str:
    cover_path = resolve_item_cover_path(data_dir, item)
    if cover_path is None:
        return ""

    try:
        with Image.open(cover_path) as image:
            return perceptual_hash_image(image)
    except Exception:
        return ""


def hamming_hex(left: str, right: str) -> int:
    if not left or not right:
        return 64
    try:
        return (int(left, 16) ^ int(right, 16)).bit_count()
    except ValueError:
        return 64


def source_path_for_archive(item: dict) -> Path | None:
    if item.get("kind") != "archive":
        return None
    source_path = Path(str(item.get("sourcePath", "") or ""))
    if not source_path.exists() or not source_path.is_file():
        return None
    return source_path


def archive_content_signature(data_dir: Path, item: dict) -> str:
    archive_path = source_path_for_archive(item)
    if archive_path is None:
        return ""

    password = get_archive_password(data_dir, archive_path)
    try:
        pages = archive_pages(item, password=password)
    except (ArchivePasswordRequiredError, ArchivePasswordIncorrectError):
        return ""
    except Exception:
        return ""

    if not pages:
        return ""

    parts = [str(len(pages))]
    try:
        if archive_path.suffix.casefold() == ".zip":
            with zipfile.ZipFile(archive_path) as archive:
                for page in pages:
                    page_bytes = read_zip_member(archive, page["member"], password)
                    parts.append(hashlib.md5(page_bytes).hexdigest())
        else:
            reader = get_external_reader()
            if reader is None:
                return ""
            for page in pages:
                page_bytes = reader.read_file(archive_path, page["member"], password=password)
                parts.append(hashlib.md5(page_bytes).hexdigest())
    except (ArchivePasswordRequiredError, ArchivePasswordIncorrectError):
        return ""
    except Exception:
        return ""

    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()


def duplicate_visual_sample_indexes(page_count: int) -> list[int]:
    if page_count <= 0:
        return []
    indexes = {0, 1, 2, 3, 4, page_count - 5, page_count - 4, page_count - 3, page_count - 2, page_count - 1}
    indexes.update({page_count // 4, page_count // 2, (page_count * 3) // 4})
    return sorted(index for index in indexes if 0 <= index < page_count)


def archive_visual_hashes(data_dir: Path, item: dict, indexes: list[int] | None = None) -> list[str]:
    archive_path = source_path_for_archive(item)
    if archive_path is None:
        return []

    password = get_archive_password(data_dir, archive_path)
    try:
        pages = archive_pages(item, password=password)
    except (ArchivePasswordRequiredError, ArchivePasswordIncorrectError):
        return []
    except Exception:
        return []

    if not pages:
        return []

    if indexes is None:
        target_indexes = set(range(len(pages)))
    else:
        target_indexes = {index for index in indexes if 0 <= index < len(pages)}
    if not target_indexes:
        return []

    hashes: list[str] = []
    try:
        if archive_path.suffix.casefold() == ".zip":
            with zipfile.ZipFile(archive_path) as archive:
                for page_index, page in enumerate(pages):
                    if page_index not in target_indexes:
                        continue
                    page_bytes = read_zip_member(archive, page["member"], password)
                    with Image.open(io.BytesIO(page_bytes)) as image:
                        hashes.append(perceptual_hash_image(image))
        else:
            reader = get_external_reader()
            if reader is None:
                return []
            for page_index, page in enumerate(pages):
                if page_index not in target_indexes:
                    continue
                page_bytes = reader.read_file(archive_path, page["member"], password=password)
                with Image.open(io.BytesIO(page_bytes)) as image:
                    hashes.append(perceptual_hash_image(image))
    except (ArchivePasswordRequiredError, ArchivePasswordIncorrectError):
        return []
    except Exception:
        return []

    return hashes


def archive_visual_duplicate_metrics(
    data_dir: Path,
    left: dict,
    right: dict,
    visual_hash_cache: dict[str, list[str]],
    indexes: list[int] | None = None,
) -> dict | None:
    left_id = str(left.get("id", "") or "")
    right_id = str(right.get("id", "") or "")
    if not left_id or not right_id:
        return None

    left_count = int(left.get("pageCount", 0) or 0)
    right_count = int(right.get("pageCount", 0) or 0)
    if left_count <= 0 or left_count != right_count:
        return None

    index_key = "all" if indexes is None else ",".join(str(index) for index in indexes)
    left_cache_key = f"{left_id}|{index_key}"
    right_cache_key = f"{right_id}|{index_key}"
    if left_cache_key not in visual_hash_cache:
        visual_hash_cache[left_cache_key] = archive_visual_hashes(data_dir, left, indexes=indexes)
    if right_cache_key not in visual_hash_cache:
        visual_hash_cache[right_cache_key] = archive_visual_hashes(data_dir, right, indexes=indexes)

    left_hashes = visual_hash_cache.get(left_cache_key, [])
    right_hashes = visual_hash_cache.get(right_cache_key, [])
    if not left_hashes or len(left_hashes) != len(right_hashes):
        return None

    distances = [hamming_hex(left_hash, right_hash) for left_hash, right_hash in zip(left_hashes, right_hashes)]
    if not distances:
        return None

    max_distance = max(distances)
    average_distance = sum(distances) / len(distances)
    if max_distance <= DUPLICATE_VISUAL_PAGE_MAX_DISTANCE and average_distance <= DUPLICATE_VISUAL_AVG_MAX_DISTANCE:
        return {
            "maxDistance": max_distance,
            "averageDistance": round(average_distance, 3),
            "pageCount": len(distances),
        }
    return None


def folder_directory_signature(item: dict) -> str:
    try:
        pages = folder_pages(item)
    except Exception:
        return ""

    if not pages:
        return ""

    parts = [str(len(pages))]
    for page in pages:
        path = Path(str(page.get("path", "") or ""))
        if not path.exists() or not path.is_file():
            return ""
        try:
            parts.append(file_digest(path, "md5"))
        except Exception:
            return ""

    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()


def duplicate_item_payload(item: dict) -> dict:
    return {
        "id": item.get("id", ""),
        "name": item.get("name", ""),
        "kind": item.get("kind", ""),
        "pageCount": int(item.get("pageCount", 0) or 0),
        "path": item.get("sourcePath") or item.get("comicPath") or "",
    }


def find_duplicates(data_dir: Path, ids: list[str], progress_file: Path | None = None) -> dict:
    library = ensure_library(data_dir)
    all_items = [item for item in library.get("items", []) if isinstance(item, dict)]
    items_by_id = {str(item.get("id", "")): item for item in all_items if str(item.get("id", ""))}

    requested_ids: list[str] = []
    seen_requested: set[str] = set()
    for raw_id in ids:
        item_id = str(raw_id or "").strip()
        if item_id and item_id in items_by_id and item_id not in seen_requested:
            requested_ids.append(item_id)
            seen_requested.add(item_id)

    if not requested_ids:
        requested_ids = list(items_by_id.keys())
        seen_requested = set(requested_ids)

    query_items = [items_by_id[item_id] for item_id in requested_ids if item_id in items_by_id]
    append_progress_event(
        progress_file,
        "duplicate_start",
        f"查重：开始，选中 {len(query_items)} 本，全库 {len(all_items)} 本",
        selectedCount=len(query_items),
        libraryCount=len(all_items),
    )

    groups: list[dict] = []
    exact_pair_keys: set[tuple[str, str]] = set()

    def group_intersects_query(item_ids: list[str]) -> bool:
        return any(item_id in seen_requested for item_id in item_ids)

    def add_group(kind: str, reason: str, item_ids: list[str], confidence: int, **extra: object) -> None:
        unique_ids = sorted({item_id for item_id in item_ids if item_id in items_by_id})
        if len(unique_ids) < 2 or not group_intersects_query(unique_ids):
            return

        if kind == "exact":
            pair_keys: list[tuple[str, str]] = []
            has_new_pair = False
            for left_index in range(len(unique_ids)):
                for right_index in range(left_index + 1, len(unique_ids)):
                    pair_key = (unique_ids[left_index], unique_ids[right_index])
                    pair_keys.append(pair_key)
                    if pair_key not in exact_pair_keys:
                        has_new_pair = True
            if not has_new_pair:
                return
            for pair_key in pair_keys:
                exact_pair_keys.add(pair_key)

        group_id = hashlib.sha1(f"{kind}|{reason}|{'|'.join(unique_ids)}".encode("utf-8")).hexdigest()[:16]
        group = {
            "id": group_id,
            "kind": kind,
            "reason": reason,
            "confidence": confidence,
            "itemIds": unique_ids,
            "items": [duplicate_item_payload(items_by_id[item_id]) for item_id in unique_ids],
        }
        group.update(extra)
        groups.append(group)

    cover_hashes: dict[str, str] = {}
    for index, item in enumerate(all_items, start=1):
        item_id = str(item.get("id", "") or "")
        if item_id:
            cover_hashes[item_id] = cover_phash(data_dir, item)
        if index == 1 or index == len(all_items) or index % 50 == 0:
            append_progress_event(
                progress_file,
                "duplicate_progress",
                f"查重：计算封面指纹 {index}/{len(all_items)}",
                current=index,
                total=len(all_items),
            )

    archives_by_size: dict[int, list[dict]] = defaultdict(list)
    for item in all_items:
        path = source_path_for_archive(item)
        if path is None:
            continue
        try:
            archives_by_size[path.stat().st_size].append(item)
        except OSError:
            continue

    archive_candidates: list[dict] = []
    for candidates in archives_by_size.values():
        candidate_ids = [str(item.get("id", "") or "") for item in candidates]
        if len(candidates) > 1 and group_intersects_query(candidate_ids):
            archive_candidates.extend(candidates)

    archive_hashes: dict[tuple[str, str], list[str]] = defaultdict(list)
    archive_digest_cache: dict[str, str] = {}
    for index, item in enumerate(archive_candidates, start=1):
        item_id = str(item.get("id", "") or "")
        source_path = source_path_for_archive(item)
        if not item_id or source_path is None:
            continue
        append_progress_event(
            progress_file,
            "duplicate_progress",
            f"查重：计算压缩包 SHA {index}/{len(archive_candidates)}：{item.get('name', '')}",
            current=index,
            total=len(archive_candidates),
            id=item_id,
        )
        try:
            digest_key = str(source_path)
            if digest_key not in archive_digest_cache:
                archive_digest_cache[digest_key] = file_digest(source_path, "sha256")
            digest = archive_digest_cache[digest_key]
            internal_path = normalize_internal_path(str(item.get("internalPath", "") or ""))
            archive_hashes[(digest, internal_path)].append(item_id)
        except Exception:
            continue

    for (digest, internal_path), item_ids in archive_hashes.items():
        add_group("exact", "archive_sha256", item_ids, 100, digest=digest, internalPath=internal_path)

    archives_by_pages_and_cover: dict[tuple[int, str], list[dict]] = defaultdict(list)
    for item in all_items:
        if item.get("kind") != "archive":
            continue
        item_id = str(item.get("id", "") or "")
        page_count = int(item.get("pageCount", 0) or 0)
        cover_hash = cover_hashes.get(item_id, "")
        if item_id and page_count > 0 and cover_hash:
            archives_by_pages_and_cover[(page_count, cover_hash)].append(item)

    archive_content_candidates: list[dict] = []
    for candidates in archives_by_pages_and_cover.values():
        candidate_ids = [str(item.get("id", "") or "") for item in candidates]
        if len(candidates) > 1 and group_intersects_query(candidate_ids):
            archive_content_candidates.extend(candidates)

    archive_content_hashes: dict[str, list[str]] = defaultdict(list)
    archive_content_cache: dict[str, str] = {}
    for index, item in enumerate(archive_content_candidates, start=1):
        item_id = str(item.get("id", "") or "")
        source_path = source_path_for_archive(item)
        if not item_id or source_path is None:
            continue
        append_progress_event(
            progress_file,
            "duplicate_progress",
            f"查重：计算压缩包内容签名 {index}/{len(archive_content_candidates)}：{item.get('name', '')}",
            current=index,
            total=len(archive_content_candidates),
            id=item_id,
        )
        signature_key = f"{source_path}|{normalize_internal_path(str(item.get('internalPath', '') or ''))}"
        if signature_key not in archive_content_cache:
            archive_content_cache[signature_key] = archive_content_signature(data_dir, item)
        signature = archive_content_cache[signature_key]
        if signature:
            archive_content_hashes[signature].append(item_id)

    for signature, item_ids in archive_content_hashes.items():
        add_group("exact", "archive_content_signature", item_ids, 100, digest=signature)

    folders_by_page_count: dict[int, list[dict]] = defaultdict(list)
    for item in all_items:
        if item.get("kind") == "folder":
            folders_by_page_count[int(item.get("pageCount", 0) or 0)].append(item)

    folder_candidates: list[dict] = []
    for candidates in folders_by_page_count.values():
        candidate_ids = [str(item.get("id", "") or "") for item in candidates]
        if len(candidates) > 1 and group_intersects_query(candidate_ids):
            folder_candidates.extend(candidates)

    folder_signatures: dict[str, list[str]] = defaultdict(list)
    for index, item in enumerate(folder_candidates, start=1):
        item_id = str(item.get("id", "") or "")
        if not item_id:
            continue
        append_progress_event(
            progress_file,
            "duplicate_progress",
            f"查重：计算文件夹目录签名 {index}/{len(folder_candidates)}：{item.get('name', '')}",
            current=index,
            total=len(folder_candidates),
            id=item_id,
        )
        signature = folder_directory_signature(item)
        if signature:
            folder_signatures[signature].append(item_id)

    for signature, item_ids in folder_signatures.items():
        add_group("exact", "folder_directory_signature", item_ids, 100, digest=signature)

    exact_item_ids_for_similar = {
        item_id
        for pair_key in exact_pair_keys
        for item_id in pair_key
    }

    seen_similar_pairs: set[tuple[str, str]] = set()
    similar_candidate_pairs: list[tuple[dict, dict, int, str, str]] = []
    for index, item in enumerate(query_items, start=1):
        item_id = str(item.get("id", "") or "")
        item_hash = cover_hashes.get(item_id, "")
        if not item_id or not item_hash or item_id in exact_item_ids_for_similar:
            continue

        item_page_count = int(item.get("pageCount", 0) or 0)
        for other in all_items:
            other_id = str(other.get("id", "") or "")
            if not other_id or other_id == item_id or other_id in exact_item_ids_for_similar:
                continue

            pair_key = tuple(sorted((item_id, other_id)))
            if pair_key in seen_similar_pairs or pair_key in exact_pair_keys:
                continue

            other_hash = cover_hashes.get(other_id, "")
            if not other_hash:
                continue

            other_page_count = int(other.get("pageCount", 0) or 0)
            if item_page_count and other_page_count and abs(item_page_count - other_page_count) > 3:
                continue

            distance = hamming_hex(item_hash, other_hash)
            if distance <= 8:
                seen_similar_pairs.add(pair_key)
                similar_candidate_pairs.append((item, other, distance, item_hash, other_hash))

        if index == 1 or index == len(query_items) or index % 25 == 0:
            append_progress_event(
                progress_file,
                "duplicate_progress",
                f"查重：比较封面相似度 {index}/{len(query_items)}",
                current=index,
                total=len(query_items),
            )

    visual_hash_cache: dict[str, list[str]] = {}
    for index, (item, other, distance, item_hash, other_hash) in enumerate(similar_candidate_pairs, start=1):
        if distance > DUPLICATE_VISUAL_COVER_MAX_DISTANCE:
            continue
        if item.get("kind") != "archive" or other.get("kind") != "archive":
            continue
        item_id = str(item.get("id", "") or "")
        other_id = str(other.get("id", "") or "")
        if not item_id or not other_id:
            continue
        if int(item.get("pageCount", 0) or 0) != int(other.get("pageCount", 0) or 0):
            continue
        page_count = int(item.get("pageCount", 0) or 0)
        sample_indexes = duplicate_visual_sample_indexes(page_count)

        append_progress_event(
            progress_file,
            "duplicate_progress",
            f"查重：抽样复核视觉重复 {index}/{len(similar_candidate_pairs)}：{item.get('name', '')}",
            current=index,
            total=len(similar_candidate_pairs),
            id=item_id,
        )
        metrics = archive_visual_duplicate_metrics(data_dir, item, other, visual_hash_cache, indexes=sample_indexes)
        if metrics is None:
            continue
        used_sample = True
        if page_count <= DUPLICATE_VISUAL_FULL_CONFIRM_MAX_PAGES:
            append_progress_event(
                progress_file,
                "duplicate_progress",
                f"查重：全页确认视觉重复 {index}/{len(similar_candidate_pairs)}：{item.get('name', '')}",
                current=index,
                total=len(similar_candidate_pairs),
                id=item_id,
            )
            full_metrics = archive_visual_duplicate_metrics(data_dir, item, other, visual_hash_cache)
            if full_metrics is None:
                continue
            metrics = full_metrics
            used_sample = False
        add_group(
            "exact",
            "archive_visual_signature",
            [item_id, other_id],
            99,
            coverDistance=distance,
            maxPageDistance=metrics["maxDistance"],
            averagePageDistance=metrics["averageDistance"],
            comparedPages=metrics["pageCount"],
            sampled=used_sample,
        )

    exact_item_ids_for_similar = {
        item_id
        for pair_key in exact_pair_keys
        for item_id in pair_key
    }

    series_by_cover: dict[str, list[dict]] = defaultdict(list)
    for item in all_items:
        item_id = str(item.get("id", "") or "")
        if not item_id or item_id in exact_item_ids_for_similar:
            continue
        cover_hash = cover_hashes.get(item_id, "")
        page_count = int(item.get("pageCount", 0) or 0)
        if cover_hash and page_count > 0:
            series_by_cover[cover_hash].append(item)

    for cover_hash, candidates in series_by_cover.items():
        candidate_ids = [str(item.get("id", "") or "") for item in candidates]
        if len(candidate_ids) < 2 or not group_intersects_query(candidate_ids):
            continue
        page_counts = [int(item.get("pageCount", 0) or 0) for item in candidates if int(item.get("pageCount", 0) or 0) > 0]
        if len(page_counts) < 2 or (max(page_counts) - min(page_counts)) <= 3:
            continue
        add_group(
            "series",
            "same_cover_different_page_count",
            candidate_ids,
            88,
            coverHash=cover_hash,
            minPageCount=min(page_counts),
            maxPageCount=max(page_counts),
        )

    for item, other, distance, item_hash, other_hash in similar_candidate_pairs:
        item_id = str(item.get("id", "") or "")
        other_id = str(other.get("id", "") or "")
        pair_key = tuple(sorted((item_id, other_id)))
        if pair_key in exact_pair_keys or item_id in exact_item_ids_for_similar or other_id in exact_item_ids_for_similar:
            continue
        confidence = max(65, 96 - (distance * 4))
        add_group(
            "similar",
            "cover_phash",
            [item_id, other_id],
            confidence,
            distance=distance,
            leftHash=item_hash,
            rightHash=other_hash,
        )

    summary = duplicate_summary_from_groups(groups)
    exact_groups = int(summary["exactGroups"])
    similar_groups = int(summary["similarGroups"])
    series_groups = int(summary.get("seriesGroups", 0))
    exact_duplicate_ids = list(summary["exactItemIds"])
    similar_item_ids = list(summary["similarItemIds"])
    series_item_ids = list(summary.get("seriesItemIds", []))
    result = {
        "version": 1,
        "createdAt": utc_now(),
        "queryIds": requested_ids,
        "libraryCount": len(all_items),
        "groups": groups,
        "summary": summary,
    }

    append_progress_event(
        progress_file,
        "duplicate_done",
        f"查重完成：完全重复 {exact_groups} 组，重复项 {len(exact_duplicate_ids)} 本；相似版本 {similar_groups} 组，涉及 {len(similar_item_ids)} 本；连载/系列 {series_groups} 组，涉及 {len(series_item_ids)} 本",
        exactGroups=exact_groups,
        similarGroups=similar_groups,
        seriesGroups=series_groups,
        duplicateItems=len(exact_duplicate_ids),
        similarItems=len(similar_item_ids),
        seriesItems=len(series_item_ids),
    )
    return result


def duplicate_summary_from_groups(groups: list[dict]) -> dict:
    exact_duplicate_ids = sorted(
        {
            str(item_id).strip()
            for group in groups
            if group.get("kind") == "exact"
            for item_id in group.get("itemIds", [])
            if str(item_id or "").strip()
        }
    )
    similar_item_ids = sorted(
        {
            str(item_id).strip()
            for group in groups
            if group.get("kind") == "similar"
            for item_id in group.get("itemIds", [])
            if str(item_id or "").strip()
        }
    )
    series_item_ids = sorted(
        {
            str(item_id).strip()
            for group in groups
            if group.get("kind") == "series"
            for item_id in group.get("itemIds", [])
            if str(item_id or "").strip()
        }
    )
    matched_item_ids = sorted(set(exact_duplicate_ids).union(similar_item_ids).union(series_item_ids))
    exact_groups = sum(1 for group in groups if group.get("kind") == "exact")
    similar_groups = sum(1 for group in groups if group.get("kind") == "similar")
    series_groups = sum(1 for group in groups if group.get("kind") == "series")
    return {
        "totalGroups": len(groups),
        "exactGroups": exact_groups,
        "similarGroups": similar_groups,
        "seriesGroups": series_groups,
        "duplicateItems": len(exact_duplicate_ids),
        "uniqueItems": len(exact_duplicate_ids),
        "itemIds": exact_duplicate_ids,
        "exactItemIds": exact_duplicate_ids,
        "similarItems": len(similar_item_ids),
        "similarItemIds": similar_item_ids,
        "seriesItems": len(series_item_ids),
        "seriesItemIds": series_item_ids,
        "matchedItems": len(matched_item_ids),
        "matchedItemIds": matched_item_ids,
    }


def dismiss_duplicate_items(data_dir: Path, item_ids: list[str]) -> dict:
    target_ids = {str(item_id).strip() for item_id in item_ids if str(item_id or "").strip()}
    if not target_ids:
        raise RuntimeError("没有可移出的重复项。")

    result_path = data_dir / "duplicates.json"
    if not result_path.exists():
        return {
            "removed": [],
            "removedCount": 0,
            "removedGroups": 0,
            "summary": duplicate_summary_from_groups([]),
        }

    with result_path.open("r", encoding="utf-8-sig") as handle:
        data = json.load(handle)

    groups = list(data.get("groups", []))
    next_groups: list[dict] = []
    removed_ids: set[str] = set()
    removed_groups = 0

    for group in groups:
        old_ids = [str(item_id).strip() for item_id in group.get("itemIds", []) if str(item_id or "").strip()]
        next_ids = [item_id for item_id in old_ids if item_id not in target_ids]
        removed_ids.update(item_id for item_id in old_ids if item_id in target_ids)

        if len(next_ids) < 2:
            if len(next_ids) != len(old_ids):
                removed_groups += 1
            continue

        next_group = dict(group)
        next_group["itemIds"] = next_ids
        if isinstance(next_group.get("items"), list):
            next_group["items"] = [
                item
                for item in next_group["items"]
                if isinstance(item, dict) and str(item.get("id", "")).strip() in next_ids
            ]
        next_groups.append(next_group)

    data["groups"] = next_groups
    data["summary"] = duplicate_summary_from_groups(next_groups)
    data["updatedAt"] = utc_now()
    data["lastDismissedItemIds"] = sorted(removed_ids)
    write_json_file(result_path, data)
    return {
        "removed": sorted(removed_ids),
        "removedCount": len(removed_ids),
        "removedGroups": removed_groups,
        "summary": data["summary"],
    }


def print_json(data: dict) -> None:
    sys.stdout.write(json.dumps(data, ensure_ascii=False, indent=2))
    sys.stdout.write("\n")


def write_json_file(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = temp_json_path(path)
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    replace_file_with_retry(temp_path, path)


def read_paths_file(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8-sig") as handle:
        data = json.load(handle)
    if not isinstance(data, list):
        raise RuntimeError("路径清单格式无效。")
    return [str(value) for value in data if str(value or "").strip()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Scan local manga folders and archives.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list")
    list_parser.add_argument("--data-dir", required=True)

    add_parser = subparsers.add_parser("add")
    add_parser.add_argument("--data-dir", required=True)
    add_parser.add_argument("--protect-favorite", action="store_true")
    add_parser.add_argument("--summary-only", action="store_true")
    add_parser.add_argument("--output-file")
    add_parser.add_argument("--paths-file")
    add_parser.add_argument("--progress-file")
    add_parser.add_argument("paths", nargs="*")

    remove_parser = subparsers.add_parser("remove")
    remove_parser.add_argument("--data-dir", required=True)
    remove_parser.add_argument("--summary-only", action="store_true")
    remove_parser.add_argument("--output-file")
    remove_parser.add_argument("--ids-file")
    remove_parser.add_argument("ids", nargs="*")

    add_category_parser = subparsers.add_parser("add-category")
    add_category_parser.add_argument("--data-dir", required=True)
    add_category_parser.add_argument("--name", required=True)
    add_category_parser.add_argument("--summary-only", action="store_true")

    delete_category_parser = subparsers.add_parser("delete-category")
    delete_category_parser.add_argument("--data-dir", required=True)
    delete_category_parser.add_argument("--name", required=True)
    delete_category_parser.add_argument("--summary-only", action="store_true")

    clear_user_categories_parser = subparsers.add_parser("clear-user-categories")
    clear_user_categories_parser.add_argument("--data-dir", required=True)

    reset_tag_rules_parser = subparsers.add_parser("reset-tag-rules")
    reset_tag_rules_parser.add_argument("--data-dir", required=True)

    rebuild_wnacg_tags_parser = subparsers.add_parser("rebuild-wnacg-tags")
    rebuild_wnacg_tags_parser.add_argument("--data-dir", required=True)
    rebuild_wnacg_tags_parser.add_argument("--summary-only", action="store_true")

    tag_mappings_parser = subparsers.add_parser("tag-mappings")
    tag_mappings_parser.add_argument("--data-dir", required=True)

    map_raw_tag_parser = subparsers.add_parser("map-raw-tag")
    map_raw_tag_parser.add_argument("--data-dir", required=True)
    map_raw_tag_parser.add_argument("--source", default="wnacg")
    map_raw_tag_parser.add_argument("--raw", required=True)
    map_raw_tag_parser.add_argument("--target-category", default="")
    map_raw_tag_parser.add_argument("--target-namespace", default="")
    map_raw_tag_parser.add_argument("--target-tag", default="")
    map_raw_tag_parser.add_argument("--summary-only", action="store_true")

    blacklist_raw_tag_parser = subparsers.add_parser("blacklist-raw-tag")
    blacklist_raw_tag_parser.add_argument("--data-dir", required=True)
    blacklist_raw_tag_parser.add_argument("--source", default="wnacg")
    blacklist_raw_tag_parser.add_argument("--raw", required=True)
    blacklist_raw_tag_parser.add_argument("--summary-only", action="store_true")

    keep_raw_tag_parser = subparsers.add_parser("keep-raw-tag-category")
    keep_raw_tag_parser.add_argument("--data-dir", required=True)
    keep_raw_tag_parser.add_argument("--source", default="wnacg")
    keep_raw_tag_parser.add_argument("--raw", required=True)
    keep_raw_tag_parser.add_argument("--category", default="")
    keep_raw_tag_parser.add_argument("--summary-only", action="store_true")

    blacklist_category_parser = subparsers.add_parser("blacklist-category")
    blacklist_category_parser.add_argument("--data-dir", required=True)
    blacklist_category_parser.add_argument("--name", required=True)
    blacklist_category_parser.add_argument("--summary-only", action="store_true")

    merge_category_parser = subparsers.add_parser("merge-category")
    merge_category_parser.add_argument("--data-dir", required=True)
    merge_category_parser.add_argument("--source", required=True)
    merge_category_parser.add_argument("--target", required=True)
    merge_category_parser.add_argument("--summary-only", action="store_true")

    rename_category_parser = subparsers.add_parser("rename-category")
    rename_category_parser.add_argument("--data-dir", required=True)
    rename_category_parser.add_argument("--name", required=True)
    rename_category_parser.add_argument("--new-name", required=True)
    rename_category_parser.add_argument("--summary-only", action="store_true")

    assign_category_parser = subparsers.add_parser("assign-category")
    assign_category_parser.add_argument("--data-dir", required=True)
    assign_category_parser.add_argument("--name", required=True)
    assign_category_parser.add_argument("--explicit-favorite", action="store_true")
    assign_category_parser.add_argument("--summary-only", action="store_true")
    assign_category_parser.add_argument("ids", nargs="+")

    unassign_category_parser = subparsers.add_parser("unassign-category")
    unassign_category_parser.add_argument("--data-dir", required=True)
    unassign_category_parser.add_argument("--name", required=True)
    unassign_category_parser.add_argument("--summary-only", action="store_true")
    unassign_category_parser.add_argument("ids", nargs="+")

    recognize_titles_parser = subparsers.add_parser("recognize-titles")
    recognize_titles_parser.add_argument("--data-dir", required=True)
    recognize_titles_parser.add_argument("ids", nargs="*")

    recognize_batch_parser = subparsers.add_parser("recognize-batch")
    recognize_batch_parser.add_argument("--data-dir", required=True)
    recognize_batch_parser.add_argument("--progress-file", required=True)
    recognize_batch_parser.add_argument("--pause-file", required=True)
    recognize_batch_parser.add_argument("ids", nargs="+")

    ocr_status_parser = subparsers.add_parser("ocr-status")
    ocr_status_parser.add_argument("--data-dir", required=True)
    ocr_status_parser.add_argument("--initialize", action="store_true")

    select_title_parser = subparsers.add_parser("select-title")
    select_title_parser.add_argument("--data-dir", required=True)
    select_title_parser.add_argument("--id", required=True)
    select_title_parser.add_argument("--name", required=True)

    ehtag_status_parser = subparsers.add_parser("ehtag-translation-status")
    ehtag_status_parser.add_argument("--data-dir", required=True)

    ehtag_download_parser = subparsers.add_parser("download-ehtag-translation")
    ehtag_download_parser.add_argument("--data-dir", required=True)

    classify_tags_parser = subparsers.add_parser("classify-tags")
    classify_tags_parser.add_argument("--data-dir", required=True)
    classify_tags_parser.add_argument("--delay-ms", type=int, default=TAG_SCRAPE_MIN_DELAY_MS)
    classify_tags_parser.add_argument("--delay-max-ms", type=int, default=TAG_SCRAPE_MAX_DELAY_MS)
    classify_tags_parser.add_argument("--progress-file")
    classify_tags_parser.add_argument("--output-file")
    classify_tags_parser.add_argument("--summary-only", action="store_true")
    classify_tags_parser.add_argument("ids", nargs="*")

    duplicates_parser = subparsers.add_parser("find-duplicates")
    duplicates_parser.add_argument("--data-dir", required=True)
    duplicates_parser.add_argument("--progress-file")
    duplicates_parser.add_argument("--output-file")
    duplicates_parser.add_argument("--ids-file")
    duplicates_parser.add_argument("ids", nargs="*")

    dismiss_duplicates_parser = subparsers.add_parser("dismiss-duplicates")
    dismiss_duplicates_parser.add_argument("--data-dir", required=True)
    dismiss_duplicates_parser.add_argument("--ids-file")
    dismiss_duplicates_parser.add_argument("ids", nargs="*")

    pages_parser = subparsers.add_parser("pages")
    pages_parser.add_argument("--data-dir", required=True)
    pages_parser.add_argument("--id", required=True)

    export_parser = subparsers.add_parser("export-page")
    export_parser.add_argument("--data-dir", required=True)
    export_parser.add_argument("--id", required=True)
    export_parser.add_argument("--index", type=int, required=True)

    prepare_parser = subparsers.add_parser("prepare-reader")
    prepare_parser.add_argument("--data-dir", required=True)
    prepare_parser.add_argument("--id", required=True)
    prepare_parser.add_argument("--session-id", required=True)
    prepare_parser.add_argument("--password")
    prepare_parser.add_argument("--initial-count", type=int, default=READER_INITIAL_CACHE_COUNT)

    prepare_page_parser = subparsers.add_parser("prepare-reader-page")
    prepare_page_parser.add_argument("--data-dir", required=True)
    prepare_page_parser.add_argument("--id", required=True)
    prepare_page_parser.add_argument("--session-id", required=True)
    prepare_page_parser.add_argument("--index", type=int, required=True)
    prepare_page_parser.add_argument("--password")

    prepare_window_parser = subparsers.add_parser("prepare-reader-window")
    prepare_window_parser.add_argument("--data-dir", required=True)
    prepare_window_parser.add_argument("--id", required=True)
    prepare_window_parser.add_argument("--session-id", required=True)
    prepare_window_parser.add_argument("--index", type=int, required=True)
    prepare_window_parser.add_argument("--count", type=int, default=READER_INITIAL_CACHE_COUNT)
    prepare_window_parser.add_argument("--password")

    progress_parser = subparsers.add_parser("progress")
    progress_parser.add_argument("--data-dir", required=True)
    progress_parser.add_argument("--id", required=True)
    progress_parser.add_argument("--index", type=int, required=True)

    clear_session_parser = subparsers.add_parser("clear-session-cache")
    clear_session_parser.add_argument("--data-dir", required=True)
    clear_session_parser.add_argument("--session-id", required=False)

    args = parser.parse_args(argv)
    data_dir = Path(args.data_dir)

    if args.command == "list":
        print_json(list_library(data_dir))
        return 0

    if args.command == "add":
        add_input_paths = list(args.paths)
        if args.paths_file:
            add_input_paths.extend(read_paths_file(Path(args.paths_file)))
        if not add_input_paths:
            raise RuntimeError("没有可添加的路径。")
        add_result = add_paths(
            data_dir,
            add_input_paths,
            protect_favorite=args.protect_favorite,
            include_library=not args.summary_only,
            progress_file=Path(args.progress_file) if args.progress_file else None,
        )
        if args.output_file:
            write_json_file(Path(args.output_file), add_result)
        else:
            print_json(add_result)
        return 0

    if args.command == "remove":
        remove_ids = list(args.ids)
        if args.ids_file:
            remove_ids.extend(read_paths_file(Path(args.ids_file)))
        if not remove_ids:
            raise RuntimeError("没有可移除的项目。")
        remove_result = remove_items(data_dir, remove_ids)
        if args.summary_only:
            remove_result.pop("library", None)
        if args.output_file:
            write_json_file(Path(args.output_file), remove_result)
        else:
            print_json(remove_result)
        return 0

    if args.command == "add-category":
        add_category_result = add_category(data_dir, args.name)
        if args.summary_only:
            add_category_result.pop("library", None)
        print_json(add_category_result)
        return 0

    if args.command == "delete-category":
        delete_category_result = delete_category(data_dir, args.name)
        if args.summary_only:
            delete_category_result.pop("library", None)
        print_json(delete_category_result)
        return 0

    if args.command == "clear-user-categories":
        print_json(clear_user_categories(data_dir))
        return 0

    if args.command == "reset-tag-rules":
        print_json(reset_tag_rules(data_dir))
        return 0

    if args.command == "rebuild-wnacg-tags":
        print_json(rebuild_wnacg_tag_categories(data_dir, include_library=not args.summary_only))
        return 0

    if args.command == "tag-mappings":
        print_json(list_tag_mappings(data_dir))
        return 0

    if args.command == "map-raw-tag":
        print_json(
            map_raw_tag(
                data_dir,
                args.source,
                args.raw,
                target_category=args.target_category,
                target_namespace=args.target_namespace,
                target_tag=args.target_tag,
                include_library=not args.summary_only,
            )
        )
        return 0

    if args.command == "blacklist-raw-tag":
        print_json(blacklist_raw_tag(data_dir, args.source, args.raw, include_library=not args.summary_only))
        return 0

    if args.command == "keep-raw-tag-category":
        print_json(keep_raw_tag_as_category(data_dir, args.source, args.raw, category_name=args.category, include_library=not args.summary_only))
        return 0

    if args.command == "blacklist-category":
        blacklist_result = blacklist_category(data_dir, args.name)
        if args.summary_only:
            blacklist_result.pop("library", None)
        print_json(blacklist_result)
        return 0

    if args.command == "merge-category":
        merge_result = merge_categories(data_dir, args.source, args.target)
        if args.summary_only:
            merge_result.pop("library", None)
        print_json(merge_result)
        return 0

    if args.command == "rename-category":
        rename_result = rename_category(data_dir, args.name, args.new_name)
        if args.summary_only:
            rename_result.pop("library", None)
        print_json(rename_result)
        return 0

    if args.command == "assign-category":
        print_json(update_item_category(data_dir, args.ids, args.name, "add", explicit_favorite=args.explicit_favorite, include_library=not args.summary_only))
        return 0

    if args.command == "unassign-category":
        print_json(update_item_category(data_dir, args.ids, args.name, "remove", include_library=not args.summary_only))
        return 0

    if args.command == "recognize-titles":
        print_json(recognize_titles(data_dir, args.ids))
        return 0

    if args.command == "recognize-batch":
        print_json(
            title_recognition_worker(
                data_dir=data_dir,
                item_ids=args.ids,
                progress_file=Path(args.progress_file),
                pause_file=Path(args.pause_file),
            )
        )
        return 0

    if args.command == "ocr-status":
        print_json(paddle_ocr_status(data_dir, initialize=args.initialize))
        return 0

    if args.command == "select-title":
        print_json(select_title_candidate(data_dir, args.id, args.name))
        return 0

    if args.command == "ehtag-translation-status":
        print_json(ehtag_translation_status(data_dir))
        return 0

    if args.command == "download-ehtag-translation":
        print_json(download_ehtag_translation(data_dir))
        return 0

    if args.command == "classify-tags":
        classify_result = classify_tags(
            data_dir,
            args.ids,
            delay_ms=args.delay_ms,
            delay_max_ms=args.delay_max_ms,
            progress_file=Path(args.progress_file) if args.progress_file else None,
            include_library=not args.summary_only,
        )
        if args.output_file:
            write_json_file(Path(args.output_file), classify_result)
        else:
            print_json(classify_result)
        return 0

    if args.command == "find-duplicates":
        duplicate_ids = list(args.ids)
        if args.ids_file:
            duplicate_ids.extend(read_paths_file(Path(args.ids_file)))
        duplicate_result = find_duplicates(
            data_dir,
            duplicate_ids,
            progress_file=Path(args.progress_file) if args.progress_file else None,
        )
        if args.output_file:
            write_json_file(Path(args.output_file), duplicate_result)
        else:
            print_json(duplicate_result)
        return 0

    if args.command == "dismiss-duplicates":
        dismiss_ids = list(args.ids)
        if args.ids_file:
            dismiss_ids.extend(read_paths_file(Path(args.ids_file)))
        print_json(dismiss_duplicate_items(data_dir, dismiss_ids))
        return 0

    if args.command == "pages":
        print_json(page_info(data_dir, args.id))
        return 0

    if args.command == "export-page":
        print_json(export_page(data_dir, args.id, args.index))
        return 0

    if args.command == "prepare-reader":
        print_json(prepare_reader(data_dir, args.id, args.session_id, password=args.password, initial_count=args.initial_count))
        return 0

    if args.command == "prepare-reader-page":
        print_json(prepare_reader_page(data_dir, args.id, args.session_id, args.index, password=args.password))
        return 0

    if args.command == "prepare-reader-window":
        print_json(
            prepare_reader_window(
                data_dir,
                args.id,
                args.session_id,
                args.index,
                count=args.count,
                password=args.password,
            )
        )
        return 0

    if args.command == "progress":
        print_json(save_reading_progress(data_dir, args.id, args.index))
        return 0

    if args.command == "clear-session-cache":
        print_json(clear_session_cache(data_dir, args.session_id))
        return 0

    parser.error("unknown command")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

