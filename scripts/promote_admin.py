"""One-shot script to promote 1234@gmail.com to Django superuser.
Run on Railway via: railway ssh "/opt/venv/bin/python /app/scripts/promote_admin.py"
"""
import django, os, sys
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'chamdiemtudong.settings')
django.setup()

from django.contrib.auth.models import User

EMAIL = '1234@gmail.com'
u = User.objects.filter(email=EMAIL).first()
if not u:
    print(f'[FAIL] User with email {EMAIL} NOT FOUND. Hiện có các user:')
    for x in User.objects.values_list('email', flat=True):
        print('  -', x)
    sys.exit(1)

print(f'[BEFORE] {u} is_superuser={u.is_superuser} is_staff={u.is_staff}')
u.is_superuser = True
u.is_staff = True
u.save()
print(f'[AFTER ] {u} is_superuser={u.is_superuser} is_staff={u.is_staff}')
print('OK — user is now admin.')
