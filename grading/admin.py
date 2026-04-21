from django.contrib import admin
from .models import Exam, Submission, TrainingSample, UserSettings


@admin.register(UserSettings)
class UserSettingsAdmin(admin.ModelAdmin):
    list_display = ('user', 'temp_retention_days', 'contribute_training_data', 'updated_at')
    list_filter = ('contribute_training_data', 'temp_retention_days')
    search_fields = ('user__username', 'user__email')


@admin.register(TrainingSample)
class TrainingSampleAdmin(admin.ModelAdmin):
    list_display = ('id', 'teacher', 'made', 'sbd', 'template_code', 'confidence', 'uploaded_at')
    list_filter = ('template_code', 'uploaded_at')
    search_fields = ('teacher__username', 'made', 'sbd')
    readonly_fields = ('uploaded_at',)


@admin.register(Exam)
class ExamAdmin(admin.ModelAdmin):
    list_display = ('title', 'subject', 'num_questions', 'teacher', 'submission_count', 'created_at')
    list_filter = ('subject', 'created_at')
    search_fields = ('title', 'subject')


@admin.register(Submission)
class SubmissionAdmin(admin.ModelAdmin):
    list_display = ('student_name', 'exam', 'status', 'score', 'correct_count', 'uploaded_at')
    list_filter = ('status', 'exam', 'uploaded_at')
    search_fields = ('student_name', 'student_id')
    readonly_fields = ('score', 'correct_count', 'answers_detected', 'detail_json', 'graded_at', 'processing_time')
