// إعدادات التطبيق (Market-Ready)
//
// 🔒 مهم: في نظام السوق لا يجب عرض روابط النظام داخل الواجهة.
// عدّل العناوين هنا مرة واحدة قبل البناء/النشر.
//
// Backend API Base URL (يُستخدم لطلبات الـ API داخل التطبيق).
/// ⚠️ مهم: لوحة التحكم Razor تعمل على /Admin (5101) لكنها ليست API.
// Default local backend: Visual Studio profile uses HTTPS on 5101 (HTTP is 5100).
const String kBackendBaseUrl = 'https://top-chef-res.store';

/// Admin Dashboard URL (عنوان لوحة التحكم التي يتم فتحها داخل تطبيق الإدارة).
/// مثال للنشر: https://your-domain.com/admin
// Admin dashboard (Razor) running locally.
const String kAdminDashboardUrl = 'https://top-chef-res.store/Admin/Login';

/// عناوين صفحات لوحة التحكم (ويب) للتقارير والخريطة الحية.
String adminReportsUrl() => '${kBackendBaseUrl.endsWith('/') ? kBackendBaseUrl.substring(0, kBackendBaseUrl.length - 1) : kBackendBaseUrl}/Admin/Reports';
String adminLiveMapUrl() => '${kBackendBaseUrl.endsWith('/') ? kBackendBaseUrl.substring(0, kBackendBaseUrl.length - 1) : kBackendBaseUrl}/Admin/LiveMap';
String adminSettingsWebUrl() => '${kBackendBaseUrl.endsWith('/') ? kBackendBaseUrl.substring(0, kBackendBaseUrl.length - 1) : kBackendBaseUrl}/Admin/Settings';
