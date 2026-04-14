from django import forms
from django.contrib.auth.models import User
from .models import TeacherProfile


class LoginForm(forms.Form):
    """Login form — email/password only."""
    email = forms.EmailField(
        label='Email',
        widget=forms.EmailInput(attrs={
            'class': 'form-input',
            'placeholder': 'email@truonghoc.edu.vn',
            'autofocus': True,
            'id': 'login-email',
        })
    )
    password = forms.CharField(
        label='Mật khẩu',
        widget=forms.PasswordInput(attrs={
            'class': 'form-input',
            'placeholder': '••••••••',
            'id': 'login-password',
        })
    )


class RegisterForm(forms.Form):
    """Registration form — name, email, password."""
    full_name = forms.CharField(
        label='Họ và tên',
        max_length=100,
        widget=forms.TextInput(attrs={
            'class': 'form-input',
            'placeholder': 'Nguyễn Văn An',
            'id': 'reg-name',
            'autofocus': True,
        })
    )
    email = forms.EmailField(
        label='Email',
        widget=forms.EmailInput(attrs={
            'class': 'form-input',
            'placeholder': 'email@truonghoc.edu.vn',
            'id': 'reg-email',
        })
    )
    password = forms.CharField(
        label='Mật khẩu',
        min_length=8,
        widget=forms.PasswordInput(attrs={
            'class': 'form-input',
            'placeholder': '••••••••',
            'id': 'reg-password',
        })
    )
    password_confirm = forms.CharField(
        label='Xác nhận mật khẩu',
        widget=forms.PasswordInput(attrs={
            'class': 'form-input',
            'placeholder': '••••••••',
            'id': 'reg-password-confirm',
        })
    )

    def clean_email(self):
        email = self.cleaned_data['email']
        if User.objects.filter(email=email).exists():
            raise forms.ValidationError('Email này đã được sử dụng.')
        return email

    def clean(self):
        cleaned_data = super().clean()
        pw = cleaned_data.get('password')
        pw2 = cleaned_data.get('password_confirm')
        if pw and pw2 and pw != pw2:
            self.add_error('password_confirm', 'Mật khẩu không khớp.')
        return cleaned_data


class ProfileForm(forms.ModelForm):
    """Teacher profile edit form."""
    first_name = forms.CharField(
        label='Họ',
        max_length=30,
        widget=forms.TextInput(attrs={
            'class': 'form-input',
            'placeholder': 'Nguyễn Văn',
        })
    )
    last_name = forms.CharField(
        label='Tên',
        max_length=30,
        widget=forms.TextInput(attrs={
            'class': 'form-input',
            'placeholder': 'An',
        })
    )

    class Meta:
        model = TeacherProfile
        fields = ['school', 'subject', 'phone']
        widgets = {
            'school': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Trường THPT ABC',
            }),
            'subject': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Toán, Lý, Hóa...',
            }),
            'phone': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': '0901234567',
            }),
        }
        labels = {
            'school': 'Trường',
            'subject': 'Môn dạy',
            'phone': 'Số điện thoại',
        }
