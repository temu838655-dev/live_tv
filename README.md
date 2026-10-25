# Truyền hình

Ứng dụng Android (Flutter) xem truyền hình trực tuyến: kênh Việt Nam và quốc tế, mục Bóng đá, Phim (YouTube, Internet Archive, thông tin phim từ TMDB), Yêu thích, chọn âm thanh khi kênh có nhiều track.

Hướng dẫn này giúp bạn **build file APK ngay trên GitHub** (không cần cài Flutter hay Android Studio, làm được hoàn toàn trên điện thoại) và **đăng lên Releases** để tải về.

## Các file

Tất cả nằm ở thư mục ngoài cùng, không có thư mục con (trừ `.github`), để tải lên bằng điện thoại cho dễ.

| File | Việc của nó |
|---|---|
| `main.dart`, `pubspec.yaml` | Mã nguồn ứng dụng (script tự chép `main.dart` vào `lib/` khi build) |
| `build_apk.sh` | Script build, dùng chung cho GitHub và máy cá nhân |
| `ic_launcher.png`, `ic_launcher_foreground.png` | Icon ứng dụng |
| `.github/workflows/build.yml` | Quy trình tự động build APK và tạo Release (nội dung ở Phụ lục cuối trang) |

Thư mục `android/` **không có sẵn**: mỗi lần build, script tự tạo bằng `flutter create`.

---

## Build APK trên GitHub

### Bước 1. Tạo repository

1. Đăng nhập github.com, bấm dấu **+** (góc phải trên), chọn **New repository**.
2. Đặt tên, ví dụ `live_tv`. Tick "Add a README file" cũng được, không tick cũng được.
3. Chọn **Private** (khuyên dùng, nhất là khi bạn dùng khóa API ở phần dưới) hoặc Public. Bấm **Create repository**.

> Repo Private có 2.000 phút Actions miễn phí mỗi tháng, một lần build khoảng 10 phút. Repo Public không giới hạn.

### Bước 2. Đưa mã nguồn lên (làm được trên điện thoại)

Trên điện thoại, mở menu trình duyệt và bật **Desktop site** (Trang web cho máy tính) để GitHub hiện đủ nút.

**2a. Tải 5 file lên.** Giải nén file zip, rồi trong repo bấm **Add file > Upload files**, bấm **choose your files** và chọn 5 file: `main.dart`, `pubspec.yaml`, `build_apk.sh`, `ic_launcher.png`, `ic_launcher_foreground.png`. Cuộn xuống bấm **Commit changes**. (Đừng tạo thư mục con, cả 5 file phải nằm ở ngoài cùng. Đường dẫn trang tải lên: `https://github.com/<tên-bạn>/<tên-repo>/upload/main`.)

**2b. Tạo file workflow.** Thư mục `.github` bị ẩn trên điện thoại nên ta tạo trực tiếp trên GitHub:

1. Bấm **Add file > Create new file**.
2. Ở ô tên, gõ chính xác `.github/workflows/build.yml` (gõ dấu `/` thì GitHub tự tạo thư mục).
3. Dán nội dung ở **Phụ lục** cuối trang này vào khung soạn thảo.
4. Bấm **Commit changes**.

Làm xong, trong repo phải thấy 5 file ở ngoài cùng và thư mục `.github`.

**Cách khác, dùng git trên máy tính:**

```sh
cd live_tv
git init -b main
git add .
git commit -m "Truyen hinh"
git remote add origin https://github.com/<tên-bạn>/live_tv.git
git push -u origin main
```

### Bước 3. Build thử

1. Vào tab **Actions**. Nếu GitHub hỏi có bật workflow không, bấm nút xác nhận.
2. Chọn **Build APK** ở cột trái, bấm **Run workflow**, **để trống ô tag**, bấm nút xanh **Run workflow**.
3. Đợi khoảng 8 đến 12 phút cho đến khi có dấu tick xanh.
4. Mở lần chạy đó, cuộn xuống mục **Artifacts**, tải `live_tv-apk` (một file zip, bên trong là file `.apk`).

### Bước 4. Tạo bản Releases

**Cách 1 (không cần dòng lệnh):** tab **Actions > Build APK > Run workflow**, điền tag vào ô, ví dụ `v1.0.0`, bấm **Run workflow**.

**Cách 2 (dùng git):**

```sh
git tag v1.0.0
git push origin v1.0.0
```

Khi chạy xong, vào trang chính của repo, mục **Releases** ở cột phải (hoặc phía dưới trên điện thoại) sẽ có bản `v1.0.0` kèm file `live_tv-1.0.0.apk`. Bản sau chỉ cần đổi số tag (`v1.0.1`, `v1.1.0`, ...). Đường dẫn bản mới nhất: `https://github.com/<tên-bạn>/live_tv/releases/latest`.

Số trong tag trở thành số phiên bản của ứng dụng. Số phiên bản nội bộ tự tăng theo mỗi lần chạy workflow, nên bản mới luôn cài đè được bản cũ (với điều kiện cùng chữ ký, xem phần "Ký APK").

### Bước 5. Cài lên điện thoại

1. Tải file `.apk` về điện thoại (trên Release, hoặc giải nén file zip Artifacts).
2. Mở file, cho phép **Cài đặt từ nguồn không xác định** khi máy hỏi.
3. Nếu Google Play Protect cảnh báo, chọn **Vẫn cài đặt**. Đây là cảnh báo chung cho mọi APK không lên Google Play.

---

## Khóa API (tùy chọn)

Không có khóa thì Truyền hình trực tiếp, Bóng đá, Yêu thích và "Phim kinh điển miễn phí" (Internet Archive) vẫn dùng bình thường. Hai khóa dưới đây mở thêm phần phim:

| Tên Secret | Dùng cho | Cách lấy |
|---|---|---|
| `TMDB_KEY` | Tab "Thông tin phim" (poster, mô tả, nơi xem tại Việt Nam) | themoviedb.org, đăng ký, **Settings > API**, lấy **API Key** (loại v3, không phải "Read Access Token") |
| `YOUTUBE_KEY` | Phim Việt Nam, lồng tiếng, nước ngoài từ YouTube | console.cloud.google.com, tạo project, bật **YouTube Data API v3**, **Credentials > Create credentials > API key**. Nên giới hạn khóa chỉ dùng cho YouTube Data API v3 |

Thêm khóa: trên GitHub vào repo, **Settings > Secrets and variables > Actions > New repository secret**, nhập đúng tên ở bảng và dán giá trị. Sau đó chạy lại **Build APK**.

> Khóa được nhúng vào file APK. Ai tải được APK đều có thể trích khóa ra. Hãy dùng repo **Private**, hoặc chỉ dùng khóa miễn phí đã giới hạn như trên.

---

## Ký APK bằng khóa riêng (tùy chọn)

Mặc định APK được ký bằng khóa debug, và **khóa này khác nhau ở mỗi lần build**. Cài lần đầu không sao, nhưng cài đè bản mới lên bản cũ sẽ báo lỗi (phải gỡ bản cũ, mất danh sách yêu thích). Nếu muốn cập nhật đè, tạo một khóa riêng, dùng mãi về sau (cần máy tính có JDK):

1. Tạo khóa, nhớ mật khẩu bạn đặt:
   ```sh
   keytool -genkeypair -v -keystore release.jks -alias livetv -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Đổi file khóa sang chuỗi base64 để dán vào GitHub:
   - Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks")) | Set-Clipboard`
   - macOS: `base64 -i release.jks | pbcopy`
   - Linux: `base64 -w0 release.jks`
3. Thêm 4 Secrets (cùng chỗ với khóa API):

   | Tên | Giá trị |
   |---|---|
   | `KEYSTORE_BASE64` | chuỗi base64 ở bước 2 |
   | `KEYSTORE_PASSWORD` | mật khẩu keystore |
   | `KEY_ALIAS` | `livetv` (đúng alias ở bước 1) |
   | `KEY_PASSWORD` | mật khẩu khóa (nếu trùng mật khẩu keystore thì có thể bỏ qua) |

4. **Sao lưu file `release.jks` và mật khẩu** ở nơi an toàn. Mất khóa là không cập nhật đè được nữa. Tuyệt đối không đưa file này lên GitHub (`.gitignore` đã chặn sẵn).

Ở log bước "Build APK" sẽ hiện dòng `Da ky bang khoa rieng` khi khóa được dùng.

---

## Build trên máy cá nhân (tùy chọn)

Cần Flutter và Android SDK đã cài, rồi chạy trong thư mục dự án:

```sh
sh build_apk.sh
```

Kết quả nằm ở `dist/live_tv-<phiên bản>.apk`. Có thể đặt biến môi trường `TMDB_KEY`, `YOUTUBE_KEY` như trên GitHub.

---

## Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| Tab Actions không có "Build APK" | Thiếu `.github/workflows/build.yml`. Làm lại Bước 2b, chú ý tên file gõ chính xác |
| Tạo Release báo `Resource not accessible by integration` | **Settings > Actions > General > Workflow permissions**, chọn **Read and write permissions**, Save, chạy lại |
| Build đỏ, báo không thấy `build_apk.sh` hoặc `pubspec.yaml` | 5 file ở Bước 2a chưa nằm ở ngoài cùng repo. Tải lại cho đúng chỗ |
| Cài đè báo "App not installed" hoặc xung đột | Khác chữ ký. Gỡ bản cũ rồi cài lại, hoặc cấu hình khóa riêng ở trên |
| Build đỏ ở bước "Build APK" | Mở log bước đó, chép vài dòng lỗi cuối để được hỗ trợ. Có thể ghim phiên bản Flutter bằng cách thêm `flutter-version: "3.x.x"` vào bước "Cài Flutter" trong `build.yml` |
| Một số kênh không phát | Nguồn IPTV miễn phí thay đổi liên tục. Thử lại, chuyển kênh khác, hoặc kéo xuống ở Trang chủ để làm mới danh sách |

## Nguồn dữ liệu

Danh sách kênh lấy từ [iptv-org](https://github.com/iptv-org/iptv), thông tin phim từ TMDB (nơi xem do JustWatch cung cấp), video từ YouTube và Internet Archive. Ứng dụng không lưu trữ nội dung; chỉ nên dùng cho mục đích cá nhân.

---

## Phụ lục: nội dung `.github/workflows/build.yml`

Dán nguyên văn vào file ở Bước 2b.

```yaml
name: Build APK

# Cách dùng:
#  - Build thử:      tab Actions > Build APK > Run workflow (để trống ô tag) > tải APK ở mục Artifacts.
#  - Tạo bản Release: Run workflow và điền tag (vd v1.0.0), hoặc đẩy tag:  git tag v1.0.0 && git push origin v1.0.0
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
    inputs:
      tag:
        description: "Tag để tạo Release (vd v1.0.0). Để trống = chỉ build, không tạo Release"
        required: false
        default: ""

# Cần quyền ghi để tạo Release
permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    env:
      TAG: ${{ github.event_name == 'push' && github.ref_name || inputs.tag }}
    steps:
      - name: Lấy mã nguồn
        uses: actions/checkout@v4

      - name: Cài Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Cài Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Cache Gradle
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: gradle-${{ runner.os }}-${{ hashFiles('pubspec.yaml') }}
          restore-keys: gradle-${{ runner.os }}-

      - name: Chuẩn bị khóa ký (nếu có)
        env:
          KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}
        run: |
          if [ -n "$KEYSTORE_BASE64" ]; then
            printf '%s' "$KEYSTORE_BASE64" | base64 -d > "$RUNNER_TEMP/release.jks"
            echo "KEYSTORE_FILE=$RUNNER_TEMP/release.jks" >> "$GITHUB_ENV"
            echo "Đã nạp khóa ký riêng."
          else
            echo "Không có KEYSTORE_BASE64: APK sẽ ký bằng khóa debug."
          fi

      - name: Build APK
        env:
          TMDB_KEY: ${{ secrets.TMDB_KEY }}
          YOUTUBE_KEY: ${{ secrets.YOUTUBE_KEY }}
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
          BUILD_NUMBER: ${{ github.run_number }}
        run: |
          if [ -n "$TAG" ]; then export BUILD_NAME="${TAG#v}"; fi
          sh build_apk.sh

      - name: Lưu APK vào Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: live_tv-apk
          path: dist/*.apk
          if-no-files-found: error

      - name: Đăng lên Releases
        if: env.TAG != ''
        env:
          GH_TOKEN: ${{ github.token }}
          GH_REPO: ${{ github.repository }}
        run: |
          APK=$(ls dist/*.apk | head -n 1)
          cat > "$RUNNER_TEMP/notes.md" <<'EOF'
          **Cách cài:** tải file `.apk` ở mục *Assets* bên dưới về điện thoại Android, mở file và cho phép "Cài đặt từ nguồn không xác định" khi được hỏi.

          Nếu cài đè lên bản cũ báo lỗi, hãy gỡ bản cũ rồi cài lại (chỉ xảy ra khi chưa cấu hình khóa ký riêng, xem README).
          EOF
          if gh release view "$TAG" >/dev/null 2>&1; then
            gh release upload "$TAG" "$APK" --clobber
          else
            gh release create "$TAG" "$APK" \
              --title "Truyền hình $TAG" \
              --notes-file "$RUNNER_TEMP/notes.md" \
              --target "$GITHUB_SHA"
          fi
```

