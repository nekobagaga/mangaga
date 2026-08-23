from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SCANNER = ROOT / "src" / "manga_scanner.py"


def load_scanner_module():
    spec = importlib.util.spec_from_file_location("manga_scanner", SCANNER)
    if spec is None or spec.loader is None:
        raise AssertionError("Unable to load scanner module.")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_image(path: Path, color: tuple[int, int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (320, 480), color)
    image.save(path)


def run_scanner(data_dir: Path, *paths: Path) -> dict:
    proc = subprocess.run(
        [sys.executable, str(SCANNER), "add", "--data-dir", str(data_dir), *(str(path) for path in paths)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if proc.returncode != 0:
        raise AssertionError(proc.stderr or proc.stdout)
    return json.loads(proc.stdout)


def run_command(data_dir: Path, *args: str) -> dict:
    proc = subprocess.run(
        [sys.executable, str(SCANNER), *args, "--data-dir", str(data_dir)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if proc.returncode != 0:
        raise AssertionError(proc.stderr or proc.stdout)
    return json.loads(proc.stdout)


def run_failing_command(data_dir: Path, *args: str) -> str:
    proc = subprocess.run(
        [sys.executable, str(SCANNER), *args, "--data-dir", str(data_dir)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if proc.returncode == 0:
        raise AssertionError(f"Command unexpectedly succeeded: {proc.stdout}")
    return proc.stderr or proc.stdout


def main() -> int:
    scanner_module = load_scanner_module()
    if not scanner_module.name_needs_title_recognition("95fd07df66c0e3b8269da911a259ffea"):
        raise AssertionError("Hash-like names should trigger title OCR.")
    if scanner_module.name_needs_title_recognition("海贼王第001话"):
        raise AssertionError("Normal display names should not trigger title OCR.")
    parsed_title = scanner_module.parse_title_search_seeds("[社团名 (作者名)] 文本名称 (C102) [汉化组]")
    if parsed_title["circle"] != "社团名" or parsed_title["artist"] != "作者名" or parsed_title["title"] != "文本名称":
        raise AssertionError(f"Title parser did not extract common name parts: {parsed_title}")
    parsed_wnacg_title = scanner_module.parse_title_search_seeds(
        "[OXIDE_Lab (おきえん)] 鬼哭 参 -鬼姫崩落淫悦魔宴- [中国翻訳][DL版]"
    )
    if parsed_wnacg_title["title"] != "鬼哭 参 -鬼姫崩落淫悦魔宴":
        raise AssertionError(f"Trailing release labels were not stripped: {parsed_wnacg_title}")
    if scanner_module.build_wnacg_search_query(parsed_wnacg_title) != "鬼哭 参":
        raise AssertionError(f"WNACG query was not simplified for recall: {parsed_wnacg_title}")
    with tempfile.TemporaryDirectory(prefix="manga-shelf-status-") as status_temp:
        status_data_dir = Path(status_temp)
        ehtag_status = scanner_module.ehtag_translation_status(status_data_dir)
        status_path = str(ehtag_status.get("path", "")).replace("\\", "/")
        if ehtag_status.get("available") or not status_path.endswith("ehtag-translation/db.text.json"):
            raise AssertionError(f"EhTagTranslation status path is wrong: {ehtag_status}")
        cli_ehtag_status = run_command(status_data_dir, "ehtag-translation-status")
        if "url" not in cli_ehtag_status or "db.text.json" not in cli_ehtag_status.get("path", ""):
            raise AssertionError(f"EhTagTranslation CLI status is wrong: {cli_ehtag_status}")
        ocr_status = scanner_module.paddle_ocr_status(status_data_dir, initialize=False)
        if "installCommand" not in ocr_status or "cachePath" not in ocr_status:
            raise AssertionError(f"OCR status is missing fields: {ocr_status}")
        cli_ocr_status = run_command(status_data_dir, "ocr-status")
        if "installed" not in cli_ocr_status or "available" not in cli_ocr_status:
            raise AssertionError(f"OCR CLI status is wrong: {cli_ocr_status}")

    original_translation_mode = os.environ.get("MANGAGA_TAG_TRANSLATION_MODE")
    original_lookup_ehtag = scanner_module.lookup_ehtag_translation
    original_google_translate = scanner_module.google_translate_text
    try:
        os.environ["MANGAGA_TAG_TRANSLATION_MODE"] = "online"
        scanner_module.lookup_ehtag_translation = lambda data_dir, namespace, tag: ""
        scanner_module.google_translate_text = lambda text, source_lang="en", target_lang="zh-CN": "在线翻译"
        online_library = {"tagTranslations": {}}
        online_name = scanner_module.translate_tag_display_name(Path.cwd(), online_library, "female", "online only tag")
        if online_name != "在线翻译":
            raise AssertionError(f"Online translation mode was not used: {online_name}; {online_library}")
        os.environ["MANGAGA_TAG_TRANSLATION_MODE"] = "none"
        none_library = {"tagTranslations": {}}
        none_name = scanner_module.translate_tag_display_name(Path.cwd(), none_library, "female", "online only tag")
        if none_name is not None:
            raise AssertionError(f"None translation mode should not translate: {none_name}; {none_library}")
    finally:
        if original_translation_mode is None:
            os.environ.pop("MANGAGA_TAG_TRANSLATION_MODE", None)
        else:
            os.environ["MANGAGA_TAG_TRANSLATION_MODE"] = original_translation_mode
        scanner_module.lookup_ehtag_translation = original_lookup_ehtag
        scanner_module.google_translate_text = original_google_translate
    wnacg_html = """
    <li class="li gallary_item">
      <div class="pic_box cate-1">
        <a href="/photos-index-aid-264437.html" title="[OXIDE_Lab (おきえん)] <em>鬼哭</em> <em>参</em> -鬼姫崩落淫悦魔宴- [中国翻訳][DL版]">
          <img alt="[OXIDE_Lab (おきえん)] <em>鬼哭</em> <em>参</em> -鬼姫崩落淫悦魔宴- [中国翻訳][DL版]" src="//example.invalid/cover.jpg" />
        </a>
      </div>
      <div class="info">
        <div class="title">
          <a href="/photos-index-aid-264437.html" title="[OXIDE_Lab (おきえん)] <em>鬼哭</em> <em>参</em> -鬼姫崩落淫悦魔宴- [中国翻訳][DL版]">[OXIDE_Lab (おきえん)] <em>鬼哭</em> <em>参</em> -鬼姫崩落淫悦魔宴- [中国翻訳][DL版]</a>
        </div>
        <div class="info_col">42張圖片，創建於2024-08-28 01:52:44</div>
      </div>
    </li>
    """
    wnacg_results = scanner_module.parse_wnacg_search_results(wnacg_html)
    if not wnacg_results or wnacg_results[0]["id"] != "264437":
        raise AssertionError(f"WNACG result was not parsed: {wnacg_results}")
    if wnacg_results[0]["title"] != "[OXIDE Lab (おきえん)] 鬼哭 参 -鬼姫崩落淫悦魔宴- [中国翻訳][DL版]":
        raise AssertionError(f"WNACG title was truncated by highlighted tags: {wnacg_results}")
    if wnacg_results[0]["filecount"] != 42:
        raise AssertionError(f"WNACG search page count was not parsed: {wnacg_results}")

    fake_tag_translations = {
        "parody:honkai star rail": "崩坏星穹铁道",
        "female:crotch tattoo": "胯部纹身",
        "female:inverted nipples": "内陷乳头",
        "female:bondage": "束缚",
        "female:anal": "肛交",
        "female:anal intercourse": "肛交",
        "female:lolicon": "萝莉",
        "female:netorare": "NTR",
    }
    scanner_module.lookup_ehtag_translation = lambda data_dir, namespace, tag: fake_tag_translations.get(
        scanner_module.eh_tag_key(namespace, tag),
        "",
    )

    tag_library = {"categories": [], "categoryRecords": [], "tagTranslations": {}}
    tag_item = {"id": "tag-test", "name": "Tag Test", "categories": []}
    added_tag_categories = scanner_module.apply_eh_tags_to_item(
        Path.cwd(),
        tag_library,
        tag_item,
        {
            "query": "Tag Test",
            "score": 88.0,
            "url": "https://exhentai.org/g/1/abcdef/",
            "gallery": {
                "gid": 1,
                "token": "abcdef",
                "title": "Tag Test",
                "filecount": "2",
                "tags": [
                    "parody:honkai star rail",
                    "female:crotch tattoo",
                    "female:inverted nipples",
                    "female:anal",
                    "female:anal intercourse",
                    "language:chinese",
                    "artist:kie",
                    "male:first person perspective",
                    "other:variant set",
                    "artist:test artist",
                ],
            },
        },
    )
    expected_tag_categories = {"崩坏星穹铁道", "胯部纹身", "内陷乳头", "爆肛"}
    if set(added_tag_categories.get("categories", [])) != expected_tag_categories:
        raise AssertionError(f"EH tags were not translated into category names: {added_tag_categories}")
    tag_records = tag_library.get("categoryRecords", [])
    if len(tag_records) != 5:
        raise AssertionError(f"Blacklisted or untranslated tags were retained: {tag_records}")
    if not any(record.get("sourceNamespace") == "parody" and record.get("sourceTag") == "honkai star rail" for record in tag_records):
        raise AssertionError(f"English tag record was not retained: {tag_records}")
    if [record.get("name") for record in tag_records].count("爆肛") != 2:
        raise AssertionError(f"Synonymous EH tags were not grouped under the canonical category: {tag_records}")

    wnacg_library = {"categories": [], "categoryRecords": [], "tagTranslations": dict(fake_tag_translations)}
    wnacg_item = {"id": "wnacg-tag-test", "name": "WNACG Tag Test", "categories": []}
    wnacg_added_tags = scanner_module.apply_wnacg_tags_to_item(
        Path.cwd(),
        wnacg_library,
        wnacg_item,
        {
            "query": "WNACG Tag Test",
            "score": 96.0,
            "url": "https://www.wnacg.com/photos-index-aid-264437.html",
            "gallery": {
                "id": "264437",
                "title": "WNACG Tag Test",
                "filecount": 42,
                "tags": ["崩坏星穹铁道", "胯部纹身", "內陷乳頭", "綁縛", "肛交", "爆肛", "蘿莉", "NTR", "中文", "乱七八糟"],
            },
        },
    )
    expected_wnacg_categories = expected_tag_categories.union({"束缚", "萝莉", "NTR"})
    if set(wnacg_added_tags.get("categories", [])) != expected_wnacg_categories:
        raise AssertionError(f"WNACG tags were not mapped through EH translations: {wnacg_added_tags}")
    if "中文" not in wnacg_added_tags.get("unmappedTags", []) or "乱七八糟" not in wnacg_added_tags.get("unmappedTags", []):
        raise AssertionError(f"Unmapped WNACG tags were not reported: {wnacg_added_tags}")
    if wnacg_item.get("rawTags", {}).get("wnacg") != ["崩坏星穹铁道", "胯部纹身", "內陷乳頭", "綁縛", "肛交", "爆肛", "蘿莉", "NTR", "中文", "乱七八糟"]:
        raise AssertionError(f"WNACG raw tags were not retained: {wnacg_item}")
    if any(record.get("sourceNamespace") == "wnacg" for record in wnacg_library.get("categoryRecords", [])):
        raise AssertionError(f"WNACG direct tag category was created: {wnacg_library}")

    with tempfile.TemporaryDirectory(prefix="manga-shelf-tag-synonym-") as tag_temp:
        tag_data_dir = Path(tag_temp)
        scanner_module.save_library(
            tag_data_dir,
            {
                "version": 1,
                "items": [
                    {
                        "id": "synonym-item",
                        "name": "Synonym Item",
                        "categories": ["肛交"],
                        "rawTagCategories": {"wnacg": {"肛交": ["肛交"]}},
                    }
                ],
                "categories": ["肛交"],
                "categoryRecords": [
                    {
                        "id": scanner_module.stable_tag_record_id("female", "anal"),
                        "name": "肛交",
                        "kind": "tag",
                        "source": "exhentai",
                        "sourceNamespace": "female",
                        "sourceTag": "anal",
                        "editableName": True,
                    }
                ],
                "tagTranslations": dict(fake_tag_translations),
            },
        )
        synonym_library = scanner_module.ensure_library(tag_data_dir)
        synonym_item = synonym_library["items"][0]
        if "爆肛" not in synonym_library.get("categories", []) or "肛交" in synonym_library.get("categories", []):
            raise AssertionError(f"Synonym category was not migrated: {synonym_library}")
        if synonym_item.get("categories") != ["爆肛"]:
            raise AssertionError(f"Synonym item category was not migrated: {synonym_item}")
        if synonym_item.get("rawTagCategories", {}).get("wnacg", {}).get("肛交") != ["爆肛"]:
            raise AssertionError(f"Synonym raw tag category was not migrated: {synonym_item}")

    with tempfile.TemporaryDirectory(prefix="manga-shelf-tag-map-") as tag_temp:
        tag_data_dir = Path(tag_temp)
        scanner_module.save_library(
            tag_data_dir,
            {
                "version": 1,
                "items": [
                    {
                        "id": "raw-map-item",
                        "name": "Raw Map Item",
                        "categories": [],
                        "rawTags": {"wnacg": ["父女", "綁縛"]},
                    }
                ],
                "categories": [],
                "categoryRecords": [],
                "tagTranslations": dict(fake_tag_translations),
            },
        )
        kept_raw = scanner_module.keep_raw_tag_as_category(tag_data_dir, "wnacg", "父女", include_library=True)
        kept_item = kept_raw["library"]["items"][0]
        if "父女" not in kept_item.get("categories", []):
            raise AssertionError(f"Raw tag was not kept as custom category: {kept_raw}")
        mapped_raw = scanner_module.map_raw_tag(tag_data_dir, "wnacg", "綁縛", target_category="束缚", include_library=True)
        mapped_item = mapped_raw["library"]["items"][0]
        if "束缚" not in mapped_item.get("categories", []):
            raise AssertionError(f"Raw tag was not mapped to EH category: {mapped_raw}")
        mapping_list = scanner_module.list_tag_mappings(tag_data_dir)
        rows_by_raw = {row["rawTag"]: row for row in mapping_list.get("rows", [])}
        if rows_by_raw.get("父女", {}).get("status") != "manual" or rows_by_raw.get("綁縛", {}).get("targetCategory") != "束缚":
            raise AssertionError(f"Tag mapping list is wrong: {mapping_list}")
        blacklisted_raw = scanner_module.blacklist_raw_tag(tag_data_dir, "wnacg", "父女", include_library=True)
        blacklisted_item = blacklisted_raw["library"]["items"][0]
        if "父女" in blacklisted_item.get("categories", []) or "wnacg:父女" not in blacklisted_raw["library"].get("tagBlacklist", []):
            raise AssertionError(f"Raw tag blacklist did not remove custom category: {blacklisted_raw}")

    with tempfile.TemporaryDirectory(prefix="manga-shelf-tag-merge-") as tag_temp:
        tag_data_dir = Path(tag_temp)
        merge_library = json.loads(json.dumps(tag_library, ensure_ascii=False))
        merge_item = json.loads(json.dumps(tag_item, ensure_ascii=False))
        scanner_module.save_library(
            tag_data_dir,
            {
                "version": 1,
                "items": [merge_item],
                "categories": merge_library["categories"],
                "categoryRecords": merge_library["categoryRecords"],
                "tagTranslations": merge_library["tagTranslations"],
            },
        )
        merged = scanner_module.merge_categories(tag_data_dir, "胯部纹身", "内陷乳头")
        if "胯部纹身" in merged["library"].get("categories", []):
            raise AssertionError(f"Source category still exists after merge: {merged}")
        merged_item = merged["library"]["items"][0]
        if "胯部纹身" in merged_item.get("categories", []) or "内陷乳头" not in merged_item.get("categories", []):
            raise AssertionError(f"Item categories were not merged: {merged_item}")
        if not any(alias.get("sourceTag") == "crotch tattoo" and alias.get("targetName") == "内陷乳头" for alias in merged["library"].get("categoryAliases", [])):
            raise AssertionError(f"Tag alias was not recorded: {merged}")

        future_item = {"id": "future", "name": "Future", "categories": []}
        reapplied_merge = scanner_module.apply_eh_tags_to_item(
            tag_data_dir,
            merged["library"],
            future_item,
            {
                "query": "Tag Test",
                "score": 88.0,
                "url": "https://exhentai.org/g/1/abcdef/",
                "gallery": {
                    "gid": 1,
                    "token": "abcdef",
                    "title": "Tag Test",
                    "filecount": "2",
                    "tags": ["female:crotch tattoo"],
                },
            },
        )
        if reapplied_merge.get("categories") != ["内陷乳头"] or future_item.get("categories") != ["内陷乳头"]:
            raise AssertionError(f"Merged tag did not redirect to target category: {reapplied_merge}; {future_item}")
        if "胯部纹身" in merged["library"].get("categories", []):
            raise AssertionError(f"Merged source category was recreated: {merged['library']}")

    with tempfile.TemporaryDirectory(prefix="manga-shelf-tag-blacklist-") as tag_temp:
        tag_data_dir = Path(tag_temp)
        scanner_module.save_library(
            tag_data_dir,
            {
                "version": 1,
                "items": [tag_item],
                "categories": tag_library["categories"],
                "categoryRecords": tag_records,
                "tagTranslations": tag_library["tagTranslations"],
            },
        )
        blacklisted = scanner_module.blacklist_category(tag_data_dir, "胯部纹身")
        if "female:crotch tattoo" not in blacklisted["library"].get("tagBlacklist", []):
            raise AssertionError(f"Tag was not added to blacklist: {blacklisted}")
        if "胯部纹身" in blacklisted["library"].get("categories", []):
            raise AssertionError(f"Blacklisted category was not removed: {blacklisted}")
        blacklisted_item = blacklisted["library"]["items"][0]
        if "胯部纹身" in blacklisted_item.get("categories", []):
            raise AssertionError(f"Blacklisted category still exists on item: {blacklisted_item}")
        if any(record.get("sourceTag") == "crotch tattoo" for record in blacklisted["library"].get("categoryRecords", [])):
            raise AssertionError(f"Blacklisted category record was not removed: {blacklisted}")

        reapplied = scanner_module.apply_eh_tags_to_item(
            tag_data_dir,
            blacklisted["library"],
            blacklisted_item,
            {
                "query": "Tag Test",
                "score": 88.0,
                "url": "https://exhentai.org/g/1/abcdef/",
                "gallery": {
                    "gid": 1,
                    "token": "abcdef",
                    "title": "Tag Test",
                    "filecount": "2",
                    "tags": ["female:crotch tattoo"],
                },
            },
        )
        if reapplied.get("categories") or "胯部纹身" in blacklisted_item.get("categories", []):
            raise AssertionError(f"Blacklisted tag was created again: {reapplied}; {blacklisted_item}")

    with tempfile.TemporaryDirectory(prefix="manga-shelf-smoke-") as temp:
        root = Path(temp)
        data_dir = root / "data"
        collection = root / "漫画合集"

        write_image(collection / "海贼王" / "第002话" / "002.jpg", (120, 40, 40))
        write_image(collection / "海贼王" / "第001话" / "010.jpg", (40, 120, 40))
        write_image(collection / "海贼王" / "第001话" / "001.jpg", (40, 40, 120))
        write_image(collection / "火影忍者" / "001.webp", (120, 120, 40))
        hash_named_folder = root / "95fd07df66c0e3b8269da911a259ffea"
        write_image(hash_named_folder / "001.jpg", (80, 80, 80))

        archive_source = root / "zip-source"
        write_image(archive_source / "作品A" / "第010话" / "001.png", (20, 100, 180))
        write_image(archive_source / "作品A" / "第002话" / "001.png", (180, 100, 20))
        archive_path = root / "压缩合集.zip"
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for image_path in archive_source.rglob("*"):
                if image_path.is_file():
                    archive.write(image_path, image_path.relative_to(archive_source).as_posix())

        first = run_scanner(data_dir, collection, archive_path, hash_named_folder)
        names = [item["name"] for item in first["library"]["items"]]

        expected = {
            "海贼王第001话",
            "海贼王第002话",
            "火影忍者",
            "作品A第002话",
            "作品A第010话",
            "95fd07df66c0e3b8269da911a259ffea",
        }
        missing = expected.difference(names)
        if missing:
            raise AssertionError(f"Missing names: {sorted(missing)}; got {names}")

        covers = [data_dir / item["cover"] for item in first["library"]["items"]]
        missing_covers = [str(path) for path in covers if not path.exists()]
        if missing_covers:
            raise AssertionError(f"Missing covers: {missing_covers}")

        by_name = {item["name"]: item for item in first["library"]["items"]}
        folder_item = by_name["海贼王第001话"]
        webp_folder_item = by_name["火影忍者"]
        zip_item = by_name["作品A第002话"]
        hash_item = by_name["95fd07df66c0e3b8269da911a259ffea"]

        if folder_item.get("pageCount") != 2:
            raise AssertionError(f"Folder item pageCount is wrong: {folder_item}")
        if zip_item.get("pageCount") != 1:
            raise AssertionError(f"Zip item pageCount is wrong: {zip_item}")

        duplicate_archive = run_scanner(data_dir, archive_path)
        if duplicate_archive["added"]:
            raise AssertionError(f"Duplicate archive source was added: {duplicate_archive['added']}")
        if not any(entry.get("reason") == "duplicate_source" for entry in duplicate_archive["skipped"]):
            raise AssertionError(f"Duplicate archive source did not use the fast skip path: {duplicate_archive}")

        listed = run_command(data_dir, "list")
        listed_items = {item["id"]: item for item in listed["items"]}
        if listed_items[folder_item["id"]].get("pageCount") != 2:
            raise AssertionError(f"Listed folder pageCount is wrong: {listed_items[folder_item['id']]}")
        for category in ("热血", "恋爱", "悬疑"):
            if category not in listed["categories"]:
                raise AssertionError(f"Default category is missing: {listed}")
        if "收藏" in listed["categories"] or "喜爱" in listed["categories"] or "待确认" in listed["categories"] or "识别中" in listed["categories"]:
            raise AssertionError(f"System categories should not be custom categories: {listed}")
        if listed_items[hash_item["id"]].get("titleStatus") != "recognizing":
            raise AssertionError(f"Hash-like item was not queued for title recognition: {listed_items[hash_item['id']]}")
        if "识别中" in listed_items[hash_item["id"]]["categories"] or "待确认" in listed_items[hash_item["id"]]["categories"]:
            raise AssertionError(f"Title workflow status leaked into categories: {listed_items[hash_item['id']]}")

        library_path = data_dir / "library.json"
        library_data = json.loads(library_path.read_text(encoding="utf-8"))
        for item in library_data["items"]:
            if item["id"] == hash_item["id"]:
                item["categories"] = ["喜爱", "识别中", "待确认"]
                item.pop("titleStatus", None)
                break
        library_path.write_text(json.dumps(library_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        migrated = run_command(data_dir, "list")
        migrated_items = {item["id"]: item for item in migrated["items"]}
        migrated_hash = migrated_items[hash_item["id"]]
        if migrated_hash.get("titleStatus") != "pending" or migrated_hash["categories"] != ["喜爱"]:
            raise AssertionError(f"Legacy title status categories were not migrated: {migrated_hash}")
        run_command(data_dir, "unassign-category", "--name", "喜爱", hash_item["id"])

        blocked_favorite = run_command(data_dir, "assign-category", "--name", "喜爱", webp_folder_item["id"])
        blocked_items = {item["id"]: item for item in blocked_favorite["library"]["items"]}
        if webp_folder_item["id"] not in blocked_favorite.get("blocked", []):
            raise AssertionError(f"Implicit favorite assignment was not blocked: {blocked_favorite}")
        if "喜爱" in blocked_items[webp_folder_item["id"]]["categories"]:
            raise AssertionError(f"Implicit favorite assignment changed categories: {blocked_favorite}")

        favorite_assigned = run_command(data_dir, "assign-category", "--name", "喜爱", "--explicit-favorite", folder_item["id"])
        favorite_items = {item["id"]: item for item in favorite_assigned["library"]["items"]}
        if "喜爱" not in favorite_items[folder_item["id"]]["categories"]:
            raise AssertionError(f"Favorite category was not assigned: {favorite_assigned}")
        if "识别中" in favorite_items[folder_item["id"]]["categories"] or "待确认" in favorite_items[folder_item["id"]]["categories"]:
            raise AssertionError(f"Favorite assignment leaked into title workflow categories: {favorite_assigned}")
        run_failing_command(data_dir, "delete-category", "--name", "喜爱")

        pending_blocked = run_command(data_dir, "assign-category", "--name", "待确认", folder_item["id"])
        recognizing_blocked = run_command(data_dir, "assign-category", "--name", "识别中", folder_item["id"])
        blocked_title_items = {item["id"]: item for item in recognizing_blocked["library"]["items"]}
        if folder_item["id"] not in pending_blocked.get("blocked", []) or folder_item["id"] not in recognizing_blocked.get("blocked", []):
            raise AssertionError(f"Managed title categories should be blocked: {pending_blocked}; {recognizing_blocked}")
        if "待确认" in blocked_title_items[folder_item["id"]]["categories"] or "识别中" in blocked_title_items[folder_item["id"]]["categories"]:
            raise AssertionError(f"Managed title category assignment changed categories: {recognizing_blocked}")
        run_failing_command(data_dir, "delete-category", "--name", "待确认")
        run_failing_command(data_dir, "delete-category", "--name", "识别中")

        name_ok_recognition = run_command(data_dir, "recognize-titles", folder_item["id"])
        name_ok_items = {item["id"]: item for item in name_ok_recognition["library"]["items"]}
        if name_ok_items[folder_item["id"]].get("titleStatus"):
            raise AssertionError(f"Normal names should not enter title confirmation: {name_ok_recognition}")

        library_data = json.loads(library_path.read_text(encoding="utf-8"))
        for item in library_data["items"]:
            if item["id"] == folder_item["id"]:
                item["titleCandidates"] = [
                    {"name": "候选作品名A", "pageIndex": 0, "pageLabel": "第1页", "score": 120},
                    {"name": "候选作品名B", "pageIndex": 1, "pageLabel": "第2页", "score": 110},
                ]
                item["titleSelected"] = False
                break
        library_path.write_text(json.dumps(library_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        selected_title = run_command(data_dir, "select-title", "--id", folder_item["id"], "--name", "候选作品名B")
        selected_items = {item["id"]: item for item in selected_title["library"]["items"]}
        selected_folder = selected_items[folder_item["id"]]
        if selected_folder["name"] != "候选作品名B" or not selected_folder.get("titleSelected"):
            raise AssertionError(f"Title candidate was not selected: {selected_title}")

        worker_progress_path = data_dir / "worker-progress.json"
        worker_pause_path = data_dir / "worker-pause.flag"
        worker_result = run_command(
            data_dir,
            "recognize-batch",
            "--progress-file",
            str(worker_progress_path),
            "--pause-file",
            str(worker_pause_path),
            folder_item["id"],
        )
        if worker_result["status"] != "done" or worker_result["completed"] != 1:
            raise AssertionError(f"Recognition worker did not finish: {worker_result}")
        worker_progress = json.loads(worker_progress_path.read_text(encoding="utf-8"))
        if worker_progress["status"] != "done" or worker_progress["completed"] != 1:
            raise AssertionError(f"Recognition worker progress is wrong: {worker_progress}")

        legacy_favorite = run_command(data_dir, "assign-category", "--name", "收藏", "--explicit-favorite", zip_item["id"])
        legacy_items = {item["id"]: item for item in legacy_favorite["library"]["items"]}
        if "喜爱" not in legacy_items[zip_item["id"]]["categories"]:
            raise AssertionError(f"Legacy favorite name was not migrated: {legacy_favorite}")
        if not (collection / "海贼王" / "第001话" / "001.jpg").exists():
            raise AssertionError("Favorite category operation touched original files.")

        added_category = run_command(data_dir, "add-category", "--name", "短篇")
        if "短篇" not in added_category["library"]["categories"]:
            raise AssertionError(f"Category was not added: {added_category}")

        renamed_category = run_command(data_dir, "rename-category", "--name", "短篇", "--new-name", "短篇改")
        if "短篇改" not in renamed_category["library"]["categories"] or "短篇" in renamed_category["library"]["categories"]:
            raise AssertionError(f"Category was not renamed: {renamed_category}")

        assigned = run_command(data_dir, "assign-category", "--name", "短篇改", folder_item["id"], zip_item["id"])
        assigned_items = {item["id"]: item for item in assigned["library"]["items"]}
        if "短篇改" not in assigned_items[folder_item["id"]]["categories"]:
            raise AssertionError(f"Folder item category was not assigned: {assigned}")
        if "短篇改" not in assigned_items[zip_item["id"]]["categories"]:
            raise AssertionError(f"Zip item category was not assigned: {assigned}")

        unassigned = run_command(data_dir, "unassign-category", "--name", "短篇改", zip_item["id"])
        unassigned_items = {item["id"]: item for item in unassigned["library"]["items"]}
        if "短篇改" in unassigned_items[zip_item["id"]]["categories"]:
            raise AssertionError(f"Zip item category was not removed: {unassigned}")

        deleted_category = run_command(data_dir, "delete-category", "--name", "短篇改")
        deleted_items = {item["id"]: item for item in deleted_category["library"]["items"]}
        if "短篇改" in deleted_category["library"]["categories"]:
            raise AssertionError(f"Category was not deleted: {deleted_category}")
        if "短篇改" in deleted_items[folder_item["id"]]["categories"]:
            raise AssertionError(f"Deleted category still exists on item: {deleted_category}")
        if not (collection / "海贼王" / "第001话" / "001.jpg").exists():
            raise AssertionError("Deleting a category touched original files.")

        folder_pages = run_command(data_dir, "pages", "--id", folder_item["id"])
        if folder_pages["pageCount"] != 2:
            raise AssertionError(f"Expected 2 folder pages, got {folder_pages}")
        if [page["displayPath"] for page in folder_pages["pages"]] != ["001.jpg", "010.jpg"]:
            raise AssertionError(f"Folder pages are not naturally sorted: {folder_pages}")

        zip_pages = run_command(data_dir, "pages", "--id", zip_item["id"])
        if zip_pages["pageCount"] != 1:
            raise AssertionError(f"Expected 1 zip page, got {zip_pages}")

        exported = run_command(data_dir, "export-page", "--id", folder_item["id"], "--index", "0")
        if not Path(exported["pagePath"]).exists():
            raise AssertionError(f"Exported reader page is missing: {exported}")

        prepared_folder = run_command(
            data_dir,
            "prepare-reader",
            "--id",
            folder_item["id"],
            "--session-id",
            "session-a",
        )
        first_folder_view = Path(prepared_folder["pages"][0]["viewPath"])
        if first_folder_view != collection / "海贼王" / "第001话" / "001.jpg":
            raise AssertionError(f"JPG folder page should use original path: {prepared_folder}")

        prepared_webp = run_command(
            data_dir,
            "prepare-reader",
            "--id",
            webp_folder_item["id"],
            "--session-id",
            "session-a",
        )
        webp_view = Path(prepared_webp["pages"][0]["viewPath"])
        if not webp_view.exists() or "session-cache" not in webp_view.parts or webp_view.suffix.lower() != ".jpg":
            raise AssertionError(f"WebP folder page should be converted into session cache: {prepared_webp}")

        prepared_zip = run_command(
            data_dir,
            "prepare-reader",
            "--id",
            zip_item["id"],
            "--session-id",
            "session-a",
        )
        zip_view = Path(prepared_zip["pages"][0]["viewPath"])
        if not zip_view.exists() or "session-cache" not in zip_view.parts:
            raise AssertionError(f"Zip page should be extracted into session cache: {prepared_zip}")

        run_command(data_dir, "clear-session-cache", "--session-id", "session-a")
        if zip_view.exists() or webp_view.exists():
            raise AssertionError("Session cache was not cleared.")

        progress = run_command(data_dir, "progress", "--id", folder_item["id"], "--index", "1")
        if progress["pageIndex"] != 1:
            raise AssertionError(f"Progress was not saved: {progress}")

        second = run_scanner(data_dir, collection / "海贼王" / "第001话")
        if second["added"]:
            raise AssertionError(f"Duplicate folder was added: {second['added']}")

        cover_path = data_dir / folder_item["cover"]
        original_path = collection / "海贼王" / "第001话" / "001.jpg"
        removed = run_command(data_dir, "remove", folder_item["id"])
        if removed["removed"][0]["id"] != folder_item["id"]:
            raise AssertionError(f"Folder item was not removed: {removed}")
        if cover_path.exists():
            raise AssertionError("Cover cache was not removed.")
        if not original_path.exists():
            raise AssertionError("Original file was deleted, but deletion must only affect the shelf.")

    print("smoke ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
