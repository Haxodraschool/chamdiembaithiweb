import logging
from django.shortcuts import render, redirect
from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.dispatch import receiver
from allauth.account.signals import user_logged_in
from .forms import LoginForm, RegisterForm, ProfileForm
from .models import TeacherProfile

logger = logging.getLogger(__name__)


@receiver(user_logged_in)
def ensure_teacher_profile(sender, request, user, **kwargs):
    """Auto-create TeacherProfile on any login (including Google OAuth)."""
    TeacherProfile.objects.get_or_create(user=user)


def login_view(request):
    """Login page — email/password only, no registration."""
    if request.user.is_authenticated:
        return redirect('dashboard:index')
    
    form = LoginForm()
    
    if request.method == 'POST':
        form = LoginForm(request.POST)
        if form.is_valid():
            email = form.cleaned_data['email']
            password = form.cleaned_data['password']
            logger.warning(f'[LOGIN] Attempting login for email={email}')
            
            # Find user by email
            from django.contrib.auth.models import User
            try:
                user_obj = User.objects.get(email=email)
                logger.warning(f'[LOGIN] Found user: {user_obj.username}, check_pw={user_obj.check_password(password)}')
                
                # Try authenticate with username
                user = authenticate(request, username=user_obj.username, password=password)
                logger.warning(f'[LOGIN] authenticate result: {user}')
                
                # Fallback: if authenticate fails but password is correct, login directly
                if user is None and user_obj.check_password(password):
                    logger.warning('[LOGIN] Fallback: direct login')
                    from django.contrib.auth import login as auth_login
                    auth_login(request, user_obj, backend='django.contrib.auth.backends.ModelBackend')
                    messages.success(request, f'Chào mừng {user_obj.get_full_name() or user_obj.email}!')
                    next_url = request.GET.get('next', '/dashboard/')
                    return redirect(next_url)
                
            except User.DoesNotExist:
                user = None
                logger.warning(f'[LOGIN] No user with email={email}')
            
            if user is not None:
                login(request, user)
                messages.success(request, f'Chào mừng {user.get_full_name() or user.email}!')
                next_url = request.GET.get('next', '/dashboard/')
                return redirect(next_url)
            else:
                messages.error(request, 'Email hoặc mật khẩu không đúng.')
        else:
            logger.warning(f'[LOGIN] Form invalid: {form.errors}')
    
    return render(request, 'accounts/login.html', {'form': form})


def register_view(request):
    """Registration page — email/password, or via Google."""
    if request.user.is_authenticated:
        return redirect('dashboard:index')

    form = RegisterForm()

    if request.method == 'POST':
        form = RegisterForm(request.POST)
        if form.is_valid():
            full_name = form.cleaned_data['full_name']
            email = form.cleaned_data['email']
            password = form.cleaned_data['password']

            # Split full_name into first/last
            parts = full_name.strip().split()
            first_name = ' '.join(parts[:-1]) if len(parts) > 1 else parts[0]
            last_name = parts[-1] if len(parts) > 1 else ''

            from django.contrib.auth.models import User
            user = User.objects.create_user(
                username=email,
                email=email,
                password=password,
                first_name=first_name,
                last_name=last_name,
            )

            # Create TeacherProfile
            TeacherProfile.objects.get_or_create(user=user)

            # Create allauth EmailAddress
            try:
                from allauth.account.models import EmailAddress
                EmailAddress.objects.get_or_create(
                    user=user, email=email,
                    defaults={'verified': True, 'primary': True}
                )
            except Exception:
                pass

            # Auto-login
            login(request, user, backend='django.contrib.auth.backends.ModelBackend')
            messages.success(request, f'Chào mừng {user.get_full_name()}! Tài khoản đã được tạo.')
            return redirect('dashboard:index')

    return render(request, 'accounts/register.html', {'form': form})


def logout_view(request):
    """Logout and redirect to login page."""
    if request.method == 'POST':
        logout(request)
        messages.success(request, 'Đã đăng xuất thành công.')
    return redirect('accounts:login')


@login_required
def profile_view(request):
    """Teacher profile page."""
    profile, created = TeacherProfile.objects.get_or_create(user=request.user)
    
    if request.method == 'POST':
        form = ProfileForm(request.POST, request.FILES, instance=profile)
        if form.is_valid():
            # Update User model fields
            request.user.first_name = form.cleaned_data['first_name']
            request.user.last_name = form.cleaned_data['last_name']
            request.user.save()
            
            form.save()
            messages.success(request, 'Hồ sơ đã được cập nhật.')
            
            if request.htmx:
                return render(request, 'partials/_toast.html')
            return redirect('accounts:profile')
    else:
        form = ProfileForm(
            instance=profile,
            initial={
                'first_name': request.user.first_name,
                'last_name': request.user.last_name,
            }
        )
    
    return render(request, 'accounts/profile.html', {
        'form': form,
        'profile': profile,
    })
