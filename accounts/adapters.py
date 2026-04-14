"""
Custom allauth adapters.
- Allow email/password signup via custom register view.
- Allow social login (Google) to auto-create users.
"""
import logging
from allauth.account.adapter import DefaultAccountAdapter
from allauth.socialaccount.adapter import DefaultSocialAccountAdapter

logger = logging.getLogger('allauth')


class CustomAccountAdapter(DefaultAccountAdapter):
    """Allow signup (used by both custom register view and allauth internally)."""
    def is_open_for_signup(self, request):
        return True


class GoogleSocialAdapter(DefaultSocialAccountAdapter):
    """Allow Google OAuth signup — auto-create user on first Google login."""
    def is_open_for_signup(self, request, sociallogin):
        return True

    def on_authentication_error(self, request, provider_id, error=None, exception=None, extra_context=None):
        logger.error(f'[SOCIAL] auth error: provider={provider_id}, error={error}, exception={exception}')

    def pre_social_login(self, request, sociallogin):
        logger.info('[SOCIAL] pre_social_login called')
        super().pre_social_login(request, sociallogin)
