#!/usr/bin/env bash
# يولّد هيكل Flutter ويدمج ملفات هذا المستودع فوقه، ثم يضبط minSdk ويحذف MainActivity الافتراضية.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$SRC/../sim_data_app_build}"

if [ -e "$OUT" ]; then
  echo "المجلد موجود مسبقاً: $OUT  (احذفه أو مرّر مساراً آخر: ./setup.sh /path/to/out)"; exit 1
fi

flutter create --org com.example --project-name sim_data_app --platforms android "$OUT"

cp -r "$SRC/lib" "$SRC/assets" "$SRC/pubspec.yaml" "$OUT/"
cp -r "$SRC/android/app/src/main/." "$OUT/android/app/src/main/"

# MainActivity الافتراضية (بلا قناة sim_channel) — نحذفها لتفادي الالتباس
rm -rf "$OUT/android/app/src/main/kotlin/com/example/sim_data_app"

# minSdk = 29 (مطلوب لـ RoleManager / Call Screening)
G="$OUT/android/app/build.gradle.kts"; [ -f "$G" ] || G="$OUT/android/app/build.gradle"
sed -i -E 's/minSdk(Version)?[ =]+flutter\.minSdkVersion/minSdk = 29/' "$G"
if ! grep -qE 'minSdk(Version)?[ =]+29' "$G"; then
  echo "تحذير: لم أستطع ضبط minSdk تلقائياً. اجعله 29 يدوياً في $G"
fi

echo "تم: $OUT"
echo "الآن: cd \"$OUT\" && flutter pub get && flutter run   (جهاز حقيقي بشريحتين)"
