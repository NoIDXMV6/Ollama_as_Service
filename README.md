✅ ВНИМАНИЕ!
Убедитесь, что Ollama установлен для хотя бы одного пользователя

Шаг 1: Скачайте и установите Ollama
Перейдите: https://ollama.com/download
Скачайте OllamaSetup.exe
Запустите и установите под обычным пользователем (например, вашей учётной записью)
⚠️ Установка должна пройти успешно — появится ярлык, можно запустить.

После установки файл будет здесь:

C:\Users\ВАШ_ПОЛЬЗОВАТЕЛЬ\AppData\Local\Programs\Ollama\ollama.exe
Шаг 2: Проверьте, что файл существует
Выполните в PowerShell:

Get-ChildItem -Path "C:\Users\*\AppData\Local\Programs\Ollama\ollama.exe" | Select FullName

Если видите путь — отлично, скрипт найдёт его.

Если нет — значит, Ollama не установлен или установлен в другое место.

Запустите .\scripts\install.ps1 от администратора

PowerShell -ExecutionPolicy Bypass -File ".\scripts\install.ps1"

Введите пароль для OllamaService
Добавьте OllamaService в "Log on as a service" через secpol.msc
💡 Как добавить:

Win + R → secpol.msc
Local Policies → User Rights Assignment
Найдите: Log on as a service
Добавьте: OllamaService

# Ollama Secure Service

Ollama должна быть установлена в системе ДО запуска скрипта!

## Установка
1. Распакуйте архив в `C:\Program Files\OllamaService`
2. Запустите `double_click_install.bat` от имени администратора
3. Введите надёжный пароль при запросе

## После установки
- Ollama запускается при старте системы
- Доступен по `http://IP_ВАШЕГО_ПК:11434`
- Логи: `C:\Program Files\OllamaService\logs\`
- Модели обновляются вручную через `scripts\update_models.ps1`

## Обновление моделей
Запустите:
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files\OllamaService\scripts\update_models.ps1"

✅ Как добавить право "Log on as a service" вручную
Откройте:
secpol.msc → Local Policies → User Rights Assignment
Найдите: Log on as a service
Добавьте: OllamaService
Или используйте ntrights.exe (из Windows Resource Kit):

cmd
ntrights.exe -u OllamaService +l "SeServiceLogonRight"