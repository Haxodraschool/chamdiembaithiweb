"""Check Google OAuth configuration status — for debugging."""
from django.core.management.base import BaseCommand
from django.contrib.sites.models import Site


class Command(BaseCommand):
    help = 'Kiểm tra cấu hình Google OAuth'

    def handle(self, *args, **options):
        # 1. Site domain
        site = Site.objects.get_current()
        self.stdout.write(f'[CHECK] Site domain: {site.domain}')

        # 2. Google SocialApp
        from allauth.socialaccount.models import SocialApp
        apps = SocialApp.objects.filter(provider='google')
        self.stdout.write(f'[CHECK] Google SocialApp count: {apps.count()}')
        for a in apps:
            linked = list(a.sites.values_list('domain', flat=True))
            self.stdout.write(
                f'[CHECK]   client_id={a.client_id[:15]}... '
                f'secret={"SET" if a.secret else "EMPTY"} '
                f'sites={linked}'
            )

        if apps.count() == 0:
            self.stdout.write(self.style.ERROR(
                '[CHECK] KHÔNG CÓ Google SocialApp! '
                'Hãy set GOOGLE_CLIENT_ID + GOOGLE_CLIENT_SECRET env vars.'
            ))
        elif not apps.first().sites.exists():
            self.stdout.write(self.style.ERROR(
                '[CHECK] Google SocialApp CHƯA LINK với Site!'
            ))
        else:
            self.stdout.write(self.style.SUCCESS('[CHECK] Google OAuth OK'))
