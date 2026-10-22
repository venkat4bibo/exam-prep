# Exam Prep App - how to get your APK (no coding tools needed)

1. Create a free account at github.com and click "New repository" (name: exam-prep, Private is fine).
2. Click "uploading an existing file", then drag in everything from this folder:
   pubspec.yaml, README.md, the lib folder, the assets folder and the .github folder.
   (If the .github folder does not upload, click "Add file > Create new file", type
   .github/workflows/build.yml as the name and paste the contents of that file.)
3. Click "Commit changes".
4. Open the "Actions" tab. The "Build APK" job starts by itself (about 5-8 minutes).
   If it does not, click "Build APK" > "Run workflow".
5. When it shows a green tick, open it and download "exam-prep-apk" at the bottom.
6. Unzip it, send app-release.apk to your phone, tap it, and allow "install unknown apps".

To change questions, edit assets/questions.json (same format) and commit again.
