"""
Custom allauth adapters.
- Block email/password signup (admin-only accounts).
- Allow social login (Google) to auto-create users.
"""
from allauth.account.adapter import DefaultAccountAdapter
from allauth.socialaccount.adapter import DefaultSocialAccountAdapter


class NoSignupAccountAdapter(DefaultAccountAdapter):
    """Block public email/password registration."""
    def is_open_for_signup(self, request):
        return False


class GoogleSocialAdapter(DefaultSocialAccountAdapter):
    """Allow social (Google) signup even though email signup is closed."""
    def is_open_for_signup(self, request, sociallogin):
        return True
