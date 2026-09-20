/*
 * Pin IDirect3DDevice9::Reset / CreateDevice to the desktop size captured
 * at load. Prototype's Continue frontend still Reset()s to 1280x720 then
 * 1280x800 even when PrototypeFix CustomResolution is already 1920x1080.
 * Exclusive Reset after Continue still hung (1.2.4: VK_ERROR_OUT_OF_DATE_KHR,
 * audio alive, Alt+F4 dead). Pin size AND force Windowed=TRUE so winex11
 * keeps a real HWND.
 *
 * Loaded by the game-dir ASI loader (binkw32). IAT-hooks
 * prototypeenginef.dll -> d3d9!Direct3DCreate9.
 * Prefix DXVK d3d9 stays the IAT target.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d9.h>

#define ENGINE_DLL "prototypeenginef.dll"
#define D3D9_DLL "d3d9.dll"
#define LOG_NAME "force_desktop_res.log"

typedef IDirect3D9 *(WINAPI *Direct3DCreate9_fn)(UINT);
typedef HRESULT(WINAPI *CreateDevice_fn)(
    IDirect3D9 *, UINT, D3DDEVTYPE, HWND, DWORD, D3DPRESENT_PARAMETERS *, IDirect3DDevice9 **);
typedef HRESULT(WINAPI *Reset_fn)(IDirect3DDevice9 *, D3DPRESENT_PARAMETERS *);

static UINT g_w;
static UINT g_h;
static Direct3DCreate9_fn real_Create9;
static CreateDevice_fn real_CreateDevice;
static Reset_fn real_Reset;
static HANDLE g_log;
static volatile LONG g_iat_ok;

static void log_line(const char *fmt, ...)
{
    char buf[384];
    SYSTEMTIME st;
    va_list ap;
    DWORD wrote;
    int n;

    if (!g_log || g_log == INVALID_HANDLE_VALUE)
        return;
    GetLocalTime(&st);
    n = wsprintfA(buf, "[%02u:%02u:%02u] ", st.wHour, st.wMinute, st.wSecond);
    va_start(ap, fmt);
    n += wvsprintfA(buf + n, fmt, ap);
    va_end(ap);
    if (n < 0 || n > 370)
        return;
    buf[n++] = '\r';
    buf[n++] = '\n';
    buf[n] = 0;
    WriteFile(g_log, buf, (DWORD)n, &wrote, NULL);
}

static void capture_desktop(void)
{
    DEVMODEA dm;

    ZeroMemory(&dm, sizeof(dm));
    dm.dmSize = sizeof(dm);
    if (EnumDisplaySettingsA(NULL, ENUM_REGISTRY_SETTINGS, &dm) &&
        dm.dmPelsWidth >= 640 && dm.dmPelsHeight >= 480) {
        g_w = dm.dmPelsWidth;
        g_h = dm.dmPelsHeight;
        return;
    }
    g_w = (UINT)GetSystemMetrics(SM_CXSCREEN);
    g_h = (UINT)GetSystemMetrics(SM_CYSCREEN);
}

static void pin_pp(D3DPRESENT_PARAMETERS *pp)
{
    UINT was_w;
    UINT was_h;
    UINT was_win;

    if (!pp || !g_w || !g_h)
        return;
    was_w = pp->BackBufferWidth;
    was_h = pp->BackBufferHeight;
    was_win = (UINT)pp->Windowed;
    pp->BackBufferWidth = g_w;
    pp->BackBufferHeight = g_h;
    pp->Windowed = TRUE;
    pp->FullScreen_RefreshRateInHz = 0;
    if (was_w != g_w || was_h != g_h || !was_win)
        log_line("pin %ux%u windowed=%u -> %ux%u windowed=1",
                 was_w, was_h, was_win, g_w, g_h);
}

static HRESULT WINAPI hook_Reset(IDirect3DDevice9 *dev, D3DPRESENT_PARAMETERS *pp)
{
    pin_pp(pp);
    return real_Reset(dev, pp);
}

static int hook_vtbl(void **slot, void *hook, void **saved)
{
    DWORD old;

    if (!slot || *slot == hook)
        return 0;
    if (saved && !*saved)
        *saved = *slot;
    if (!VirtualProtect(slot, sizeof(void *), PAGE_EXECUTE_READWRITE, &old))
        return 0;
    *slot = hook;
    VirtualProtect(slot, sizeof(void *), old, &old);
    return 1;
}

static HRESULT WINAPI hook_CreateDevice(
    IDirect3D9 *d3d, UINT adapter, D3DDEVTYPE type, HWND focus, DWORD flags,
    D3DPRESENT_PARAMETERS *pp, IDirect3DDevice9 **out)
{
    HRESULT hr;
    void **vtbl;

    pin_pp(pp);
    hr = real_CreateDevice(d3d, adapter, type, focus, flags, pp, out);
    if (SUCCEEDED(hr) && out && *out) {
        vtbl = *(void ***)*out;
        if (vtbl && hook_vtbl(&vtbl[16], (void *)hook_Reset, (void **)&real_Reset))
            log_line("hooked IDirect3DDevice9::Reset");
    }
    return hr;
}

static IDirect3D9 *WINAPI hook_Create9(UINT sdk)
{
    IDirect3D9 *obj;
    void **vtbl;

    obj = real_Create9(sdk);
    if (obj) {
        vtbl = *(void ***)obj;
        if (vtbl && hook_vtbl(&vtbl[16], (void *)hook_CreateDevice, (void **)&real_CreateDevice))
            log_line("hooked IDirect3D9::CreateDevice");
    }
    return obj;
}

static int patch_iat(HMODULE mod, const char *dll, const char *func, void *hook, void **orig)
{
    BYTE *base;
    IMAGE_DOS_HEADER *dos;
    IMAGE_NT_HEADERS32 *nt;
    IMAGE_IMPORT_DESCRIPTOR *imp;
    IMAGE_THUNK_DATA32 *oth, *th;
    IMAGE_IMPORT_BY_NAME *ibn;
    DWORD old;
    const char *name;

    if (!mod)
        return 0;
    base = (BYTE *)mod;
    dos = (IMAGE_DOS_HEADER *)base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE)
        return 0;
    nt = (IMAGE_NT_HEADERS32 *)(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC)
        return 0;
    if (!nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress)
        return 0;
    imp = (IMAGE_IMPORT_DESCRIPTOR *)(base +
          nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress);
    for (; imp->Name; imp++) {
        name = (const char *)(base + imp->Name);
        if (lstrcmpiA(name, dll) != 0)
            continue;
        oth = (IMAGE_THUNK_DATA32 *)(base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
        th = (IMAGE_THUNK_DATA32 *)(base + imp->FirstThunk);
        for (; oth->u1.AddressOfData; oth++, th++) {
            if (oth->u1.Ordinal & IMAGE_ORDINAL_FLAG32)
                continue;
            ibn = (IMAGE_IMPORT_BY_NAME *)(base + oth->u1.AddressOfData);
            if (lstrcmpA((const char *)ibn->Name, func) != 0)
                continue;
            if (!VirtualProtect(&th->u1.Function, sizeof(th->u1.Function), PAGE_EXECUTE_READWRITE, &old))
                return 0;
            if (orig && !*orig)
                *orig = (void *)(ULONG_PTR)th->u1.Function;
            th->u1.Function = (ULONG_PTR)hook;
            VirtualProtect(&th->u1.Function, sizeof(th->u1.Function), old, &old);
            return 1;
        }
    }
    return 0;
}

static int try_hook(void)
{
    HMODULE engine;

    engine = GetModuleHandleA(ENGINE_DLL);
    if (!engine)
        return 0;
    if (patch_iat(engine, D3D9_DLL, "Direct3DCreate9", (void *)hook_Create9, (void **)&real_Create9)) {
        InterlockedExchange(&g_iat_ok, 1);
        log_line("IAT Direct3DCreate9 pinned to %ux%u", g_w, g_h);
        return 1;
    }
    return 0;
}

static DWORD WINAPI hook_thread(LPVOID unused)
{
    int i;

    (void)unused;
    for (i = 0; i < 200 && !g_iat_ok; i++) {
        if (try_hook())
            break;
        Sleep(50);
    }
    if (!g_iat_ok)
        log_line("IAT hook failed — engine/d3d9 import not found");
    return 0;
}

static void open_log(void)
{
    char path[MAX_PATH];
    DWORD n;

    n = GetModuleFileNameA(NULL, path, MAX_PATH);
    if (!n || n >= MAX_PATH)
        return;
    while (n > 0 && path[n - 1] != '\\' && path[n - 1] != '/')
        n--;
    path[n] = 0;
    if (lstrlenA(path) + lstrlenA(LOG_NAME) >= MAX_PATH)
        return;
    lstrcatA(path, LOG_NAME);
    g_log = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS,
                        FILE_ATTRIBUTE_NORMAL, NULL);
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason != DLL_PROCESS_ATTACH)
        return TRUE;
    DisableThreadLibraryCalls(inst);
    capture_desktop();
    open_log();
    log_line("force_desktop_res desktop %ux%u (no reshade)", g_w, g_h);
    try_hook();
    /* Never LoadLibrary in DllMain. Thread only pins Reset/CreateDevice. */
    CreateThread(NULL, 0, hook_thread, NULL, 0, NULL);
    return TRUE;
}
