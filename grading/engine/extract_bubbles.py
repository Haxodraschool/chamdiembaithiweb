"""
Extract bubble crops from answer sheet images for CNN training dataset.
Uses ENGINE RESULTS (extract_part1/2/3) to auto-label filled vs empty.

Output:
  bubble_dataset/filled/   — bubbles the engine detected as the chosen answer
  bubble_dataset/empty/    — all other bubbles

Usage:
  python -m grading.engine.extract_bubbles anh/*.jpg
"""

import cv2
import numpy as np
import os
import sys
import glob
import io

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from grading.engine.hi import (
    detect_paper_and_warp, preprocess,
    PART1_COLS, PART1_NUM_ROWS, PART1_CHOICES, BUBBLE_RADIUS,
    PART2_BLOCKS, PART2_STEP_X, PART2_STEP_Y, PART2_ROWS,
    SBD_COLS_X, MADE_COLS_X, SBD_MADE_DIGIT_Y,
    is_bubble_filled, detect_section_offsets,
    extract_part1, extract_part2,
    extract_sbd_made,
)
from PIL import Image, ExifTags

CROP_SIZE = 32
DATASET_DIR = os.path.join(os.path.dirname(__file__), 'bubble_dataset')


def load_and_warp(image_path):
    """Load image, fix EXIF, detect corners, warp to standard size."""
    image = cv2.imread(image_path)
    if image is None:
        print(f"  [ERROR] Cannot read: {image_path}")
        return None, None

    # Fix EXIF orientation
    try:
        pil_img = Image.open(image_path)
        exif = pil_img._getexif()
        if exif:
            ok = next((k for k, v in ExifTags.TAGS.items() if v == 'Orientation'), None)
            if ok and ok in exif:
                o = exif[ok]
                if o == 3: image = cv2.rotate(image, cv2.ROTATE_180)
                elif o == 6: image = cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
                elif o == 8: image = cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
    except Exception:
        pass

    # Suppress engine prints
    old_out, old_err = sys.stdout, sys.stderr
    try:
        sys.stdout = io.TextIOWrapper(io.BytesIO(), encoding='utf-8', errors='replace')
        sys.stderr = io.TextIOWrapper(io.BytesIO(), encoding='utf-8', errors='replace')
        result = detect_paper_and_warp(image, debug=False)
        warped = result["warped"]
        gray, thresh, cleaned = preprocess(warped)
        return warped, gray
    except Exception as e:
        return None, None
    finally:
        sys.stdout, sys.stderr = old_out, old_err


def crop_bubble(gray_img, cx, cy, radius=BUBBLE_RADIUS, crop_size=CROP_SIZE):
    """Crop a square region around bubble center, resize to crop_size."""
    h, w = gray_img.shape[:2]
    pad = radius + 4
    x1 = max(0, int(cx - pad))
    y1 = max(0, int(cy - pad))
    x2 = min(w, int(cx + pad))
    y2 = min(h, int(cy + pad))
    roi = gray_img[y1:y2, x1:x2]
    if roi.size == 0:
        return None
    return cv2.resize(roi, (crop_size, crop_size), interpolation=cv2.INTER_AREA)


def extract_from_image(gray_img, image_name):
    """Extract bubbles, label using engine detection results."""
    os.makedirs(os.path.join(DATASET_DIR, 'filled'), exist_ok=True)
    os.makedirs(os.path.join(DATASET_DIR, 'empty'), exist_ok=True)

    offsets = detect_section_offsets(gray_img)

    # Use engine to detect answers (auto-label ground truth)
    p1_ans, _ = extract_part1(gray_img, y_offset=offsets["part1"])
    p2_ans, _ = extract_part2(gray_img, y_offset=offsets["part2"])
    sbd_str, made_str, _ = extract_sbd_made(gray_img)

    filled_count = 0
    empty_count = 0

    for cfg in PART1_COLS:
        sx, sy = cfg["start_x"], cfg["start_y"]
        dx, dy = cfg["step_x"], cfg["step_y"]
        q_start = cfg["q_start"]
        col_rows = cfg.get("num_rows", PART1_NUM_ROWS)

        for row in range(col_rows):
            q = q_start + row
            cy = sy + row * dy + offsets["part1"]
            answer = p1_ans.get(q, '')  # Engine's detected answer

            for ci, choice in enumerate(PART1_CHOICES):
                cx = sx + ci * dx
                _, ratio = is_bubble_filled(gray_img, cx, cy)
                crop = crop_bubble(gray_img, cx, cy)
                if crop is None:
                    continue

                # Label: filled if this choice IS the detected answer
                is_filled = (choice == answer) or (answer == 'X' and ratio > 0.25)
                label = 'filled' if is_filled else 'empty'
                fname = f"{image_name}_q{q}_{choice}_r{ratio:.3f}.png"
                cv2.imwrite(os.path.join(DATASET_DIR, label, fname), crop)

                if is_filled:
                    filled_count += 1
                else:
                    empty_count += 1

    # Part II (Đúng/Sai)
    for blk in PART2_BLOCKS:
        q = blk["q"]
        sx, sy = blk["start_x"], blk["start_y"]
        q_ans = p2_ans.get(q, {})

        for ri, row_label in enumerate(PART2_ROWS):
            cy = sy + ri * PART2_STEP_Y + offsets["part2"]
            engine_ans = q_ans.get(row_label, "")
            if engine_ans not in ("Dung", "Sai"):
                continue

            for ci, col_label in enumerate(["Dung", "Sai"]):
                cx = sx + ci * PART2_STEP_X
                _, ratio = is_bubble_filled(gray_img, cx, cy)
                crop = crop_bubble(gray_img, cx, cy)
                if crop is None:
                    continue

                is_filled = (engine_ans == col_label)
                label = 'filled' if is_filled else 'empty'
                fname = f"{image_name}_p2_q{q}_{row_label}_{col_label}_r{ratio:.3f}.png"
                cv2.imwrite(os.path.join(DATASET_DIR, label, fname), crop)

                if is_filled:
                    filled_count += 1
                else:
                    empty_count += 1

    # SBD + Mã đề (digits)
    def _extract_digits(digit_str, cols_x, prefix):
        nonlocal filled_count, empty_count
        for col_idx, cx in enumerate(cols_x):
            digit_ch = digit_str[col_idx] if col_idx < len(digit_str) else "?"
            if digit_ch == "?":
                continue
            target_digit = int(digit_ch)
            for d, cy in enumerate(SBD_MADE_DIGIT_Y):
                _, ratio = is_bubble_filled(gray_img, cx, cy, check_circularity=False)
                crop = crop_bubble(gray_img, cx, cy)
                if crop is None:
                    continue

                is_filled = (d == target_digit)
                label = 'filled' if is_filled else 'empty'
                fname = f"{image_name}_{prefix}_c{col_idx}_d{d}_r{ratio:.3f}.png"
                cv2.imwrite(os.path.join(DATASET_DIR, label, fname), crop)

                if is_filled:
                    filled_count += 1
                else:
                    empty_count += 1

    _extract_digits(sbd_str, SBD_COLS_X, "sbd")
    _extract_digits(made_str, MADE_COLS_X, "made")

    return filled_count, empty_count


def main():
    # Support glob patterns
    paths = []
    for arg in sys.argv[1:]:
        expanded = glob.glob(arg)
        paths.extend(expanded if expanded else [arg])

    if not paths:
        print("Usage: python -m grading.engine.extract_bubbles <image1> [image2] ...")
        print("       python -m grading.engine.extract_bubbles anh/*.jpg")
        sys.exit(1)

    # Clear old dataset
    for sub in ['filled', 'empty']:
        d = os.path.join(DATASET_DIR, sub)
        if os.path.exists(d):
            for f in os.listdir(d):
                os.remove(os.path.join(d, f))

    total_f, total_e = 0, 0
    for i, path in enumerate(paths, 1):
        print(f"[{i}/{len(paths)}] {os.path.basename(path)} ... ", end='', flush=True)
        _, gray = load_and_warp(path)
        if gray is None:
            print("FAILED")
            continue
        name = os.path.splitext(os.path.basename(path))[0]
        f, e = extract_from_image(gray, name)
        total_f += f
        total_e += e
        print(f"filled={f}, empty={e}")

    print(f"\nTOTAL: filled={total_f}, empty={total_e}")
    print(f"Dataset: {DATASET_DIR}")


if __name__ == '__main__':
    main()
