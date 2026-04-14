"""
Custom allauth adapters.
- Allow email/password signup via custom register view.
- Allow social login (Google) to auto-create users.
"""
from allauth.account.adapter import DefaultAccountAdapter
from allauth.socialaccount.adapter import DefaultSocialAccountAdapter


class CustomAccountAdapter(DefaultAccountAdapter):
    """Allow signup (used by both custom register view and allauth internally)."""
    def is_open_for_signup(self, request):
        return True


class GoogleSocialAdapter(DefaultSocialAccountAdapter):
    """Allow Google OAuth signup — auto-create user on first Google login."""
    def is_open_for_signup(self, request, sociallogin):
        return True
