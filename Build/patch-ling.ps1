$ErrorActionPreference = 'Stop'

$utilHeaderPath = 'deps/Ling/include/Util.h'
$utilHeader = Get-Content -Raw -LiteralPath $utilHeaderPath
$utilHeader = $utilHeader.Replace('#include <vector>', "#include <vector>`n#include <array>`n#include <filesystem>")
$utilMarker = '        template <std::ranges::input_range Range, typename T>'
$utilDeclarations = @'
        static std::string convertToStr(const std::wstring& str);
        static std::wstring readTextFromBytes(const void* data, size_t size);
        static std::wstring readFileText(const std::filesystem::path& path);
        static std::array<int, 3> getVerNum(const std::wstring& path = L"");

'@
if (-not $utilHeader.Contains($utilMarker)) { throw '找不到 Ling Util.h 插入点' }
$utilHeader = $utilHeader.Replace($utilMarker, $utilDeclarations + $utilMarker)
Set-Content -LiteralPath $utilHeaderPath -Value $utilHeader -Encoding utf8

$utilSourcePath = 'deps/Ling/src/Util.cpp'
$utilSource = Get-Content -Raw -LiteralPath $utilSourcePath
$utilDefinitions = @'

    std::string Util::convertToStr(const std::wstring& str)
    {
        if (str.empty()) return {};
        int count = WideCharToMultiByte(CP_UTF8, 0, str.data(), static_cast<int>(str.size()), nullptr, 0, nullptr, nullptr);
        std::string result(static_cast<size_t>(count), '\0');
        WideCharToMultiByte(CP_UTF8, 0, str.data(), static_cast<int>(str.size()), result.data(), count, nullptr, nullptr);
        return result;
    }

    std::wstring Util::readTextFromBytes(const void* data, size_t size)
    {
        if (!data || size == 0) return {};
        const auto* bytes = static_cast<const unsigned char*>(data);
        if (size >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
            return std::wstring(reinterpret_cast<const wchar_t*>(bytes + 2), (size - 2) / sizeof(wchar_t));
        }
        size_t offset = size >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0;
        int count = MultiByteToWideChar(CP_UTF8, 0, reinterpret_cast<const char*>(bytes + offset), static_cast<int>(size - offset), nullptr, 0);
        if (count <= 0) return {};
        std::wstring result(static_cast<size_t>(count), L'\0');
        MultiByteToWideChar(CP_UTF8, 0, reinterpret_cast<const char*>(bytes + offset), static_cast<int>(size - offset), result.data(), count);
        return result;
    }

    std::wstring Util::readFileText(const std::filesystem::path& path)
    {
        HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE) return {};
        LARGE_INTEGER length{};
        if (!GetFileSizeEx(file, &length) || length.QuadPart <= 0 || length.QuadPart > MAXDWORD) { CloseHandle(file); return {}; }
        std::vector<unsigned char> bytes(static_cast<size_t>(length.QuadPart));
        DWORD read = 0;
        BOOL ok = ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr);
        CloseHandle(file);
        return ok ? readTextFromBytes(bytes.data(), read) : std::wstring{};
    }

    std::array<int, 3> Util::getVerNum(const std::wstring& requestedPath)
    {
        std::wstring path = requestedPath;
        if (path.empty()) { wchar_t buffer[MAX_PATH]{}; GetModuleFileNameW(nullptr, buffer, MAX_PATH); path = buffer; }
        DWORD ignored = 0;
        DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
        if (!size) return { 0, 0, 0 };
        std::vector<unsigned char> data(size);
        if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) return { 0, 0, 0 };
        VS_FIXEDFILEINFO* info = nullptr;
        UINT infoSize = 0;
        if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&info), &infoSize) || !info) return { 0, 0, 0 };
        return { HIWORD(info->dwFileVersionMS), LOWORD(info->dwFileVersionMS), HIWORD(info->dwFileVersionLS) };
    }
'@
$last = $utilSource.LastIndexOf('}')
if ($last -lt 0) { throw '找不到 Ling Util.cpp 插入点' }
$utilSource = $utilSource.Insert($last, $utilDefinitions)
Set-Content -LiteralPath $utilSourcePath -Value $utilSource -Encoding utf8

$d2dHeaderPath = 'deps/Ling/include/D2D.h'
$d2dHeader = Get-Content -Raw -LiteralPath $d2dHeaderPath
$d2dMarker = 'winrt::Windows::UI::Composition::CompositionDrawingSurface createDrawingSurface'
$d2dDeclaration = 'Microsoft::WRL::ComPtr<IDWriteTextLayout> makeTextLayout(const std::wstring& text, float fontSize, float width = 100000.f, float height = 100000.f);' + "`n`t`t"
if (-not $d2dHeader.Contains($d2dMarker)) { throw '找不到 Ling D2D.h 插入点' }
$d2dHeader = $d2dHeader.Replace($d2dMarker, $d2dDeclaration + $d2dMarker)
Set-Content -LiteralPath $d2dHeaderPath -Value $d2dHeader -Encoding utf8

$d2dSourcePath = 'deps/Ling/src/D2D.cpp'
$d2dSource = Get-Content -Raw -LiteralPath $d2dSourcePath
$d2dMarker = "`tComposition::CompositionDrawingSurface D2D::createDrawingSurface"
$d2dDefinition = @'
    ComPtr<IDWriteTextLayout> D2D::makeTextLayout(const std::wstring& text, float fontSize, float width, float height)
    {
        ComPtr<IDWriteTextLayout> layout;
        if (!dwriteFactory || !baseTextFormat) return layout;
        if (FAILED(dwriteFactory->CreateTextLayout(text.data(), static_cast<UINT32>(text.size()), baseTextFormat.Get(), width, height, layout.GetAddressOf()))) return {};
        layout->SetFontSize(fontSize, DWRITE_TEXT_RANGE{ 0, static_cast<UINT32>(text.size()) });
        layout->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
        return layout;
    }

'@
if (-not $d2dSource.Contains($d2dMarker)) { throw '找不到 Ling D2D.cpp 插入点' }
$d2dSource = $d2dSource.Replace($d2dMarker, $d2dDefinition + $d2dMarker)
Set-Content -LiteralPath $d2dSourcePath -Value $d2dSource -Encoding utf8
