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
        logger.info('[ADAPTER] is_open_for_signup called → True')
        return True


class GoogleSocialAdapter(DefaultSocialAccountAdapter):
    """Allow Google OAuth signup — auto-create user on first Google login."""
    def is_open_for_signup(self, request, sociallogin):
        logger.info(f'[SOCIAL-ADAPTER] is_open_for_signup: email={sociallogin.email_addresses}')
        return True

    def authentication_error(self, request, provider_id, error=None, exception=None, extra_context=None):
        logger.error(f'[SOCIAL-ADAPTER] authentication_error: provider={provider_id}, error={error}, exception={exception}, extra={extra_context}')
        super().authentication_error(request, provider_id, error, exception, extra_context)

    def pre_social_login(self, request, sociallogin):
        logger.info(f'[SOCIAL-ADAPTER] pre_social_login: user={sociallogin.user}, email={sociallogin.email_addresses}, account={sociallogin.account}')
        super().pre_social_login(request, sociallogin)
