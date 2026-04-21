"""
Management command to auto-delete old submission images based on each
user's `UserSettings.temp_retention_days`.

Usage:
    python manage.py clean_old_submissions            # real run
    python manage.py clean_old_submissions --dry-run  # preview only

Deletes only the physical image files (image, _result.jpg, _overlay.jpg,
_name.jpg). Keeps the Submission DB row for stats/history continuity.
"""
import os
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from grading.models import Submission, UserSettings


class Command(BaseCommand):
    help = "Xóa ảnh phiếu cũ theo thiết lập của từng user"

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Preview what would be deleted without actually deleting',
        )

    def handle(self, *args, **opts):
        dry = opts['dry_run']
        now = timezone.now()
        total_files = 0
        total_size = 0

        # Iterate over all users with settings
        for settings in UserSettings.objects.filter(temp_retention_days__gt=0):
            days = settings.temp_retention_days
            cutoff = now - timedelta(days=days)
            user = settings.user

            # Find submissions older than cutoff with images still on disk
            subs = Submission.objects.filter(
                teacher=user,
                uploaded_at__lt=cutoff,
            ).exclude(image='')

            count = 0
            for sub in subs:
                if not sub.image:
                    continue
                image_path = sub.image.path if hasattr(sub.image, 'path') else None
                if not image_path or not os.path.exists(image_path):
                    continue

                base = os.path.splitext(image_path)[0]
                related_paths = [
                    image_path,
                    f"{base}_result.jpg",
                    f"{base}_overlay.jpg",
                    f"{base}_name.jpg",
                ]

                for p in related_paths:
                    if os.path.exists(p):
                        sz = os.path.getsize(p)
                        total_size += sz
                        total_files += 1
                        if dry:
                            self.stdout.write(f"  [DRY] would delete: {p} ({sz} B)")
                        else:
                            try:
                                os.remove(p)
                            except OSError as e:
                                self.stderr.write(f"  ! failed {p}: {e}")

                # Clear the image FieldFile reference (but keep Submission row)
                if not dry:
                    sub.image = ''
                    sub.save(update_fields=['image'])
                count += 1

            self.stdout.write(
                f"User {user.username}: {count} submissions older than {days} days"
            )

        size_mb = total_size / (1024 * 1024)
        verb = 'would be freed' if dry else 'freed'
        self.stdout.write(self.style.SUCCESS(
            f"Done. {total_files} files {verb} ({size_mb:.2f} MB)"
        ))
