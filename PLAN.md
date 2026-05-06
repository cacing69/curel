History — Simpan curl commands ke local storage (SQLite/Hive). User bisa re-execute command dari history tanpa re-type. Ini fitur paling natural untuk terminal-style app.

Collections/Bookmarks — User bisa save curl command yang sering dipakai ke dalam folder/named collection. Mirip Postman Collections tapi terminal-style.

Environment variables — Definisikan {{base_url}}, {{api_key}}, dll. yang bisa di-swap antar environment (dev/staging/prod). Ini sangat berguna untuk developer yang bekerja dengan multiple environments.

Request body editor — Untuk POST/PUT, sediakan editor body terpisah (JSON/form-data) dengan syntax highlighting, alih-alih harus ketik full curl command manual.

Response diff — Bandingkan 2 response secara side-by-side. Sangat berguna untuk debugging API changes.

Import/export — Import curl dari clipboard/file, export history sebagai curl commands atau Postman collection JSON.