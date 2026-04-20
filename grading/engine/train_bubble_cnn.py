"""
Train a small CNN to classify bubbles as filled/empty.
Input: bubble_dataset/filled/ and bubble_dataset/empty/ (32x32 grayscale PNGs)
Output: bubble_cnn.pth (PyTorch model)

Usage:
  python -m grading.engine.train_bubble_cnn
  python -m grading.engine.train_bubble_cnn --epochs 30 --lr 0.001
"""

import os
import sys
import argparse
import numpy as np
import cv2
from pathlib import Path

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler
# sklearn lazy-imported in train() — not needed at import time for inference

DATASET_DIR = os.path.join(os.path.dirname(__file__), 'bubble_dataset')
MODEL_PATH = os.path.join(os.path.dirname(__file__), 'bubble_cnn.pth')
IMG_SIZE = 32


class BubbleDataset(Dataset):
    def __init__(self, images, labels, augment=False):
        self.images = images   # list of numpy arrays (32x32)
        self.labels = labels   # list of 0/1
        self.augment = augment

    def __len__(self):
        return len(self.images)

    def __getitem__(self, idx):
        img = self.images[idx].astype(np.float32) / 255.0
        label = self.labels[idx]

        if self.augment:
            # Random augmentation
            if np.random.random() < 0.5:
                img = np.fliplr(img).copy()
            if np.random.random() < 0.5:
                img = np.flipud(img).copy()
            if np.random.random() < 0.3:
                k = np.random.choice([1, 2, 3])
                img = np.rot90(img, k).copy()
            # Random brightness
            if np.random.random() < 0.4:
                delta = np.random.uniform(-0.1, 0.1)
                img = np.clip(img + delta, 0, 1)
            # Random noise
            if np.random.random() < 0.3:
                noise = np.random.normal(0, 0.02, img.shape).astype(np.float32)
                img = np.clip(img + noise, 0, 1)

        # To tensor: (1, 32, 32)
        tensor = torch.from_numpy(img).unsqueeze(0)
        return tensor, torch.tensor(label, dtype=torch.long)


class BubbleCNN(nn.Module):
    """Tiny CNN for bubble classification. ~15K params."""
    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 16, 3, padding=1),  # 32x32 -> 32x32
            nn.BatchNorm2d(16),
            nn.ReLU(),
            nn.MaxPool2d(2),                  # -> 16x16

            nn.Conv2d(16, 32, 3, padding=1),  # 16x16 -> 16x16
            nn.BatchNorm2d(32),
            nn.ReLU(),
            nn.MaxPool2d(2),                  # -> 8x8

            nn.Conv2d(32, 64, 3, padding=1),  # 8x8 -> 8x8
            nn.BatchNorm2d(64),
            nn.ReLU(),
            nn.AdaptiveAvgPool2d(2),          # -> 2x2
        )
        self.classifier = nn.Sequential(
            nn.Flatten(),
            nn.Dropout(0.3),
            nn.Linear(64 * 2 * 2, 32),
            nn.ReLU(),
            nn.Linear(32, 2),
        )

    def forward(self, x):
        x = self.features(x)
        x = self.classifier(x)
        return x


def load_dataset():
    """Load all images from bubble_dataset/filled and bubble_dataset/empty."""
    images, labels = [], []

    for label, folder in [(1, 'filled'), (0, 'empty')]:
        folder_path = os.path.join(DATASET_DIR, folder)
        if not os.path.exists(folder_path):
            print(f"[WARN] Missing folder: {folder_path}")
            continue
        for fname in os.listdir(folder_path):
            if not fname.endswith('.png'):
                continue
            img = cv2.imread(os.path.join(folder_path, fname), cv2.IMREAD_GRAYSCALE)
            if img is None:
                continue
            if img.shape != (IMG_SIZE, IMG_SIZE):
                img = cv2.resize(img, (IMG_SIZE, IMG_SIZE))
            images.append(img)
            labels.append(label)

    return images, labels


def train(epochs=20, lr=0.001, batch_size=32):
    images, labels = load_dataset()
    n_filled = sum(labels)
    n_empty = len(labels) - n_filled
    print(f"Dataset: {len(labels)} total ({n_filled} filled, {n_empty} empty)")

    if n_filled < 5:
        print("[ERROR] Too few filled samples. Need at least 5. Add more images.")
        sys.exit(1)

    # Split train/val (80/20)
    from sklearn.model_selection import train_test_split
    X_train, X_val, y_train, y_val = train_test_split(
        images, labels, test_size=0.2, random_state=42, stratify=labels
    )
    print(f"Train: {len(X_train)} | Val: {len(X_val)}")

    # Weighted sampler to handle class imbalance
    train_labels = np.array(y_train)
    class_counts = np.bincount(train_labels)
    weights = 1.0 / class_counts[train_labels]
    sampler = WeightedRandomSampler(weights, len(weights), replacement=True)

    train_ds = BubbleDataset(X_train, y_train, augment=True)
    val_ds = BubbleDataset(X_val, y_val, augment=False)

    train_loader = DataLoader(train_ds, batch_size=batch_size, sampler=sampler)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False)

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Device: {device}")

    model = BubbleCNN().to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=lr)
    scheduler = optim.lr_scheduler.StepLR(optimizer, step_size=10, gamma=0.5)

    best_val_acc = 0
    for epoch in range(epochs):
        # Train
        model.train()
        train_loss, train_correct, train_total = 0, 0, 0
        for imgs, lbls in train_loader:
            imgs, lbls = imgs.to(device), lbls.to(device)
            optimizer.zero_grad()
            out = model(imgs)
            loss = criterion(out, lbls)
            loss.backward()
            optimizer.step()
            train_loss += loss.item() * imgs.size(0)
            train_correct += (out.argmax(1) == lbls).sum().item()
            train_total += imgs.size(0)

        # Validate
        model.eval()
        val_correct, val_total = 0, 0
        val_tp, val_fp, val_fn = 0, 0, 0
        with torch.no_grad():
            for imgs, lbls in val_loader:
                imgs, lbls = imgs.to(device), lbls.to(device)
                out = model(imgs)
                preds = out.argmax(1)
                val_correct += (preds == lbls).sum().item()
                val_total += imgs.size(0)
                val_tp += ((preds == 1) & (lbls == 1)).sum().item()
                val_fp += ((preds == 1) & (lbls == 0)).sum().item()
                val_fn += ((preds == 0) & (lbls == 1)).sum().item()

        train_acc = train_correct / max(train_total, 1) * 100
        val_acc = val_correct / max(val_total, 1) * 100
        precision = val_tp / max(val_tp + val_fp, 1) * 100
        recall = val_tp / max(val_tp + val_fn, 1) * 100

        scheduler.step()

        marker = ''
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), MODEL_PATH)
            marker = ' *SAVED*'

        print(f"  Epoch {epoch+1:02d}/{epochs} | "
              f"Loss: {train_loss/max(train_total,1):.4f} | "
              f"Train: {train_acc:.1f}% | Val: {val_acc:.1f}% | "
              f"P: {precision:.0f}% R: {recall:.0f}%{marker}")

    print(f"\nBest val accuracy: {best_val_acc:.1f}%")
    print(f"Model saved to: {MODEL_PATH}")
    param_count = sum(p.numel() for p in model.parameters())
    print(f"Model params: {param_count:,}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--epochs', type=int, default=20)
    parser.add_argument('--lr', type=float, default=0.001)
    parser.add_argument('--batch-size', type=int, default=32)
    args = parser.parse_args()
    train(epochs=args.epochs, lr=args.lr, batch_size=args.batch_size)
