/*
 * Copyright (c) 2018 Confetti Interactive Inc.
 * 
 * This file is part of The-Forge
 * (see https://github.com/ConfettiFX/The-Forge).
 * 
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 * 
 *   http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
*/

#ifdef _WIN32

#include <ctime>
#pragma comment(lib, "WinMM.lib")
#include <windowsx.h>

#include "../../ThirdParty/OpenSource/TinySTL/vector.h"
#include "../../ThirdParty/OpenSource/TinySTL/unordered_map.h"

#include "../Interfaces/IOperatingSystem.h"
#include "../Interfaces/IPlatformEvents.h"
#include "../Interfaces/ILogManager.h"
#include "../Interfaces/ITimeManager.h"
#include "../Interfaces/IThread.h"
#include "../Interfaces/IMemoryManager.h"

#define CONFETTI_WINDOW_CLASS L"confetti"
#define MAX_KEYS 256
#define MAX_CURSOR_DELTA 200

#define GETX(l) (int(l & 0xFFFF))
#define GETY(l) (int(l) >> 16)

#define elementsOf(a) (sizeof(a) / sizeof((a)[0]))

namespace
{
	bool isCaptured = false;
}

struct KeyState
{
	bool current;   // What is the current key state?
	bool previous;  // What is the previous key state?
	bool down;      // Was the key down this frame?
	bool released;  // Was the key released this frame?
};

static bool			gWindowClassInitialized = false;
static WNDCLASSW	gWindowClass;
static bool			gAppRunning = false;

static KeyState		gKeys[MAX_KEYS] = { { false, false, false, false } };

static tinystl::vector <MonitorDesc> gMonitors;
static tinystl::unordered_map<void*, WindowsDesc*> gHWNDMap;

namespace PlatformEvents
{
	extern bool wantsMouseCapture;
	extern bool skipMouseCapture;

	extern void onWindowResize(const WindowResizeEventData* pData);
	extern void onKeyboardChar(const KeyboardCharEventData* pData);
	extern void onKeyboardButton(const KeyboardButtonEventData* pData);
	extern void onMouseMove(const MouseMoveEventData* pData);
	extern void onMouseButton(const MouseButtonEventData* pData);
	extern void onMouseWheel(const MouseWheelEventData* pData);
}

// Update the state of the keys based on state previous frame
void updateKeys(void)
{
	// Calculate each of the key states here
	for (KeyState& element : gKeys)
	{
		element.down = element.current == true;
		element.released = ((element.previous == true) && (element.current == false));
		// Record this state
		element.previous = element.current;
	}
}

// Update the given key
static void updateKeyArray(int uMsg, unsigned int wParam)
{
	KeyboardButtonEventData eventData;
	eventData.key = wParam;
	switch (uMsg)
	{
	case WM_SYSKEYDOWN:
	case WM_KEYDOWN:
		if ((0 <= wParam) && (wParam <= MAX_KEYS))
			gKeys[wParam].current = true;

		eventData.pressed = true;
		break;

	case WM_SYSKEYUP:
	case WM_KEYUP:
		if ((0 <= wParam) && (wParam <= MAX_KEYS))
			gKeys[wParam].current = false;

		eventData.pressed = false;
		break;

	default:
		break;
	}

	PlatformEvents::onKeyboardButton(&eventData);
}

static void CapturedMouseMove(HWND hwnd, int x, int y)
{
	POINT p { x, y };
	ClientToScreen(hwnd, &p);
	SetCursorPos(p.x, p.y);
}

static bool captureMouse(HWND hwnd, bool shouldCapture)
{
	if (shouldCapture != isCaptured)
	{
		static int x_capture, y_capture;
		static POINT capturedPoint;
		if (shouldCapture)
		{
			WindowsDesc* pWindow = gHWNDMap[hwnd];
			GetCursorPos(&capturedPoint);
			ScreenToClient(hwnd, &capturedPoint);
			SetCapture(hwnd);
			ShowCursor(FALSE);
			CapturedMouseMove(hwnd, getRectWidth(pWindow->windowedRect) / 2, getRectHeight(pWindow->windowedRect) / 2);
			isCaptured = true;
		}
		else
		{
			CapturedMouseMove(hwnd, capturedPoint.x, capturedPoint.y);
			ShowCursor(TRUE);
			ReleaseCapture();
			isCaptured = false;
		}
	}

	return true;
}

// Window event handler - Use as less as possible
LRESULT CALLBACK WinProc(HWND _hwnd, UINT _id, WPARAM wParam, LPARAM lParam)
{
	WindowsDesc* gCurrentWindow = NULL;
	tinystl::unordered_hash_node<void*, WindowsDesc*>* pNode = gHWNDMap.find(_hwnd).node;
	if (pNode)
		gCurrentWindow = pNode->second;
	else
		return DefWindowProcW(_hwnd, _id, wParam, lParam);

	switch (_id)
	{
	case WM_ACTIVATE:
		if (LOWORD(wParam) == WA_INACTIVE)
		{
			captureMouse(_hwnd, false);
		}
		break;

	case WM_SIZE:
		if (gCurrentWindow)
		{
			RectDesc rect = { 0 };
			if (gCurrentWindow->fullScreen)
			{
				rect = gCurrentWindow->fullscreenRect;
			}
			else
			{
				if (IsIconic(_hwnd))
					return 0;

				RECT windowRect;
				GetClientRect(_hwnd, &windowRect);
				rect = { (int)windowRect.left, (int)windowRect.top, (int)windowRect.right, (int)windowRect.bottom };
				gCurrentWindow->windowedRect = rect;
			}

			WindowResizeEventData eventData = { rect };
			PlatformEvents::onWindowResize(&eventData);
		}
		break;

	case WM_CLOSE:
	case WM_QUIT:
		gAppRunning = false;
		break;

	case WM_CHAR:
	{
		KeyboardCharEventData eventData;
		eventData.unicode = (unsigned)wParam;
		PlatformEvents::onKeyboardChar(&eventData);
		break;
	}
	case WM_MOUSEMOVE:
	{
		static int lastX = 0, lastY = 0;
		int x, y;
		x = GETX(lParam);
		y = GETY(lParam);

		MouseMoveEventData eventData;
		eventData.x = x;
		eventData.y = y;
		eventData.deltaX = x - lastX;
		eventData.deltaY = y - lastY;
		eventData.captured = isCaptured;
		eventData.pWindow = *gCurrentWindow;
		PlatformEvents::onMouseMove(&eventData);

		lastX = x;
		lastY = y;
		break;
	}
	case WM_LBUTTONDOWN:
	{
		MouseButtonEventData eventData;
		eventData.button = MOUSE_LEFT;
		eventData.pressed = true;
		eventData.x = GETX(lParam);
		eventData.y = GETY(lParam);
		if (PlatformEvents::wantsMouseCapture && !PlatformEvents::skipMouseCapture && !isCaptured)
		{
			captureMouse(_hwnd, true);
		}
		PlatformEvents::onMouseButton(&eventData);
		break;
	}
	case WM_LBUTTONUP:
	{
		MouseButtonEventData eventData;
		eventData.button = MOUSE_LEFT;
		eventData.pressed = false;
		eventData.x = GETX(lParam);
		eventData.y = GETY(lParam);
		PlatformEvents::onMouseButton(&eventData);
		break;
	}
	case WM_RBUTTONDOWN:
	{
		MouseButtonEventData eventData;
		eventData.button = MOUSE_RIGHT;
		eventData.pressed = true;
		eventData.x = GETX(lParam);
		eventData.y = GETY(lParam);
		PlatformEvents::onMouseButton(&eventData);
		break;
	}
	case WM_RBUTTONUP:
	{
		MouseButtonEventData eventData;
		eventData.button = MOUSE_RIGHT;
		eventData.pressed = false;
		eventData.x = GETX(lParam);
		eventData.y = GETY(lParam);
		PlatformEvents::onMouseButton(&eventData);
		break;
	}
	case WM_MBUTTONDOWN:
	{
		MouseButtonEventData eventData;
		eventData.button = MOUSE_MIDDLE;
		eventData.pressed = true;
		eventData.x = GETX(lParam);
		eventData.y = GETY(lParam);
		PlatformEvents::onMouseButton(&eventData);
		break;
	}
	case WM_MBUTTONUP:
	{
		MouseButtonEventData eventData;
		eventData.button = MOUSE_MIDDLE;
		eventData.pressed = false;
		eventData.x = GETX(lParam);
		eventData.y = GETY(lParam);
		PlatformEvents::onMouseButton(&eventData);
		break;
	}
	case WM_MOUSEWHEEL:
	{
		static int scroll;
		int s;

		scroll += GET_WHEEL_DELTA_WPARAM(wParam);
		s = scroll / WHEEL_DELTA;
		scroll %= WHEEL_DELTA;

		POINT point;
		point.x = GETX(lParam);
		point.y = GETY(lParam);
		ScreenToClient(_hwnd, &point);

		if (s != 0)
		{
			MouseWheelEventData eventData;
			eventData.scroll = s;
			eventData.x = point.x;
			eventData.y = point.y;
			PlatformEvents::onMouseWheel(&eventData);
		}
		break;
	}
	case WM_SYSKEYDOWN:
		if ((lParam & (1 << 29)) && (wParam == KEY_ENTER))
		{
			toggleFullscreen(gCurrentWindow);
		}
		updateKeyArray(_id, (unsigned)wParam);
		break;

	case WM_SYSKEYUP:
		updateKeyArray(_id, (unsigned)wParam);
		break;

	case WM_KEYUP:
		if (wParam == KEY_ESCAPE)
		{
			if (!isCaptured)
			{
				gAppRunning = false;
			}
			else
			{
				captureMouse(_hwnd, false);
			}
		}
		updateKeyArray(_id, (unsigned)wParam);
		break;

	case WM_KEYDOWN:
		updateKeyArray(_id, (unsigned)wParam);
		break;
	default:
		return DefWindowProcW(_hwnd, _id, wParam, lParam);
		break;
	}

	return 0;
}

static BOOL CALLBACK monitorCallback(HMONITOR pMonitor, HDC pDeviceContext, LPRECT pRect, LPARAM pParam)
{
	MONITORINFO info;
	info.cbSize = sizeof(info);
	GetMonitorInfo(pMonitor, &info);
	unsigned index = (unsigned)pParam;

	gMonitors[index].monitorRect = { (int)info.rcMonitor.left, (int)info.rcMonitor.top, (int)info.rcMonitor.right, (int)info.rcMonitor.bottom };
	gMonitors[index].workRect = { (int)info.rcWork.left, (int)info.rcWork.top, (int)info.rcWork.right, (int)info.rcWork.bottom };

	return TRUE;
}

static void collectMonitorInfo()
{
	DISPLAY_DEVICEW adapter;
	adapter.cb = sizeof(adapter);

	int found = 0;
	int size = 0;

	for (int adapterIndex = 0;; ++adapterIndex)
	{
		if (!EnumDisplayDevicesW(NULL, adapterIndex, &adapter, 0))
			break;

		if (!(adapter.StateFlags & DISPLAY_DEVICE_ACTIVE))
			continue;

		for (int displayIndex = 0; ; displayIndex++)
		{
			DISPLAY_DEVICEW display;
			HDC dc;

			display.cb = sizeof(display);

			if (!EnumDisplayDevicesW(adapter.DeviceName, displayIndex, &display, 0))
				break;

			dc = CreateDCW(L"DISPLAY", adapter.DeviceName, NULL, NULL);

			MonitorDesc desc;
			desc.modesPruned = (adapter.StateFlags & DISPLAY_DEVICE_MODESPRUNED) != 0;

			wcsncpy_s(desc.adapterName, adapter.DeviceName, elementsOf(adapter.DeviceName));
			wcsncpy_s(desc.publicAdapterName, adapter.DeviceName, elementsOf(adapter.DeviceName));
			wcsncpy_s(desc.displayName, display.DeviceName, elementsOf(display.DeviceName));
			wcsncpy_s(desc.publicDisplayName, display.DeviceName, elementsOf(display.DeviceName));

			gMonitors.push_back(desc);
			EnumDisplayMonitors(NULL, NULL, monitorCallback, gMonitors.size() - 1);

			DeleteDC(dc);

			if ((adapter.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) && displayIndex == 0)
			{
				MonitorDesc desc = gMonitors[0];
				gMonitors[0] = gMonitors[found];
				gMonitors[found] = desc;
			}

			found++;
		}
	}
}

bool isRunning()
{
	return gAppRunning;
}

void getRecommendedResolution(RectDesc* rect)
{
	*rect = RectDesc{ 0,0,1920,1080 };
}

void requestShutDown()
{
	gAppRunning = false;
}

class StaticWindowManager
{
public:
	StaticWindowManager()
	{
		if (!gWindowClassInitialized)
		{
			HINSTANCE instance = (HINSTANCE)GetModuleHandle(NULL);
			memset(&gWindowClass, 0, sizeof(gWindowClass));
			gWindowClass.style = 0;
			gWindowClass.lpfnWndProc = WinProc;
			gWindowClass.hInstance = instance;
			gWindowClass.hIcon = LoadIcon(NULL, IDI_APPLICATION);
			gWindowClass.hCursor = LoadCursor(NULL, IDC_ARROW);
			gWindowClass.lpszClassName = CONFETTI_WINDOW_CLASS;

			gAppRunning = RegisterClassW(&gWindowClass) != 0;

			if (!gAppRunning)
			{
				//Get the error message, if any.
				DWORD errorMessageID = ::GetLastError();

				if (errorMessageID != ERROR_CLASS_ALREADY_EXISTS)
				{
					LPSTR messageBuffer = nullptr;
					size_t size = FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
						NULL, errorMessageID, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), (LPSTR)&messageBuffer, 0, NULL);
					String message(messageBuffer, size);
					ErrorMsg(message.c_str());
					return;
				}
				else
				{
					gAppRunning = true;
					gWindowClassInitialized = gAppRunning;
				}
			}
		}

		collectMonitorInfo();
	}
} windowClass;

void openWindow(const char* app_name, WindowsDesc* winDesc)
{
	winDesc->fullscreenRect = { 0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN) };

	RectDesc& rect = winDesc->fullScreen ? winDesc->fullscreenRect : winDesc->windowedRect;

	WCHAR app[MAX_PATH];
	size_t charConverted = 0;
	mbstowcs_s(&charConverted, app, app_name, MAX_PATH);

	HWND hwnd = CreateWindowW(CONFETTI_WINDOW_CLASS,
		app,
		WS_OVERLAPPEDWINDOW | ((winDesc->visible) ? WS_VISIBLE : 0),
		CW_USEDEFAULT,
		CW_USEDEFAULT,
		rect.right - rect.left,
		rect.bottom - rect.top,
		NULL,
		NULL,
		(HINSTANCE)GetModuleHandle(NULL),
		0
	);

	if (hwnd)
	{
		winDesc->handle = hwnd;
		gHWNDMap.insert({ hwnd, winDesc });

		if (winDesc->visible)
		{
			if (winDesc->maximized)
			{
				ShowWindow(hwnd, SW_MAXIMIZE);
			}
			else if (winDesc->minimized)
			{
				ShowWindow(hwnd, SW_MINIMIZE);
			}
			else if (winDesc->fullScreen)
			{
				SetWindowLongPtr(hwnd, GWL_STYLE,
					WS_SYSMENU | WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS | WS_VISIBLE);
				MoveWindow(hwnd,
					winDesc->fullscreenRect.left, winDesc->fullscreenRect.top,
					winDesc->fullscreenRect.right, winDesc->fullscreenRect.bottom, TRUE);
			}
		}

		RECT clientRect;
		GetClientRect(hwnd, &clientRect);
		rect = { (int)clientRect.left, (int)clientRect.top, (int)clientRect.right, (int)clientRect.bottom };

		LOGINFOF("Created window app %s", app_name);
	}
	else
	{
		LOGERRORF("Failed to create window app %s", app_name);
	}
}

void closeWindow(const WindowsDesc* winDesc)
{
	DestroyWindow((HWND)winDesc->handle);
}

void handleMessages()
{
	MSG msg;
	msg.message = NULL;
	while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
	{
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}

	updateKeys();
}

void setWindowRect(WindowsDesc* winDesc, const RectDesc& rect)
{
	HWND hwnd = (HWND)winDesc->handle;
	RectDesc& currentRect = winDesc->fullScreen ? winDesc->fullscreenRect : winDesc->windowedRect;
	currentRect = rect;
	MoveWindow(hwnd, rect.left, rect.top, getRectWidth(rect), getRectHeight(rect), TRUE);
}

void setWindowSize(WindowsDesc* winDesc, unsigned width, unsigned height)
{
	setWindowRect(winDesc, { 0, 0, (int)width, (int)height });
}

void toggleFullscreen(WindowsDesc* winDesc)
{
	winDesc->fullScreen = !winDesc->fullScreen;

	HWND hwnd = (HWND)winDesc->handle;
	const RectDesc& rect = winDesc->fullScreen ? winDesc->fullscreenRect : winDesc->windowedRect;

	if (winDesc->fullScreen)
	{
		SetWindowLongPtr(hwnd, GWL_STYLE,
			WS_SYSMENU | WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS | WS_VISIBLE);
	}
	else
	{
		SetWindowLongPtr(hwnd, GWL_STYLE, WS_OVERLAPPEDWINDOW | WS_VISIBLE);
	}

	MoveWindow(hwnd, rect.left, rect.top, getRectWidth(rect), getRectHeight(rect), TRUE);
}

void showWindow(WindowsDesc* winDesc)
{
	winDesc->visible = true;
	ShowWindow((HWND)winDesc->handle, SW_SHOW);
}

void hideWindow(WindowsDesc* winDesc)
{
	winDesc->visible = false;
	ShowWindow((HWND)winDesc->handle, SW_HIDE);
}

void maximizeWindow(WindowsDesc* winDesc)
{
	winDesc->maximized = true;
	ShowWindow((HWND)winDesc->handle, SW_MAXIMIZE);
}

void minimizeWindow(WindowsDesc* winDesc)
{
	winDesc->maximized = false;
	ShowWindow((HWND)winDesc->handle, SW_MINIMIZE);
}

void setMousePositionRelative(const WindowsDesc* winDesc, int32_t x, int32_t y)
{
	POINT point = { (LONG)x, (LONG)y };
	ClientToScreen((HWND)winDesc->handle, &point);
	SetCursorPos(point.x, point.y);
}

MonitorDesc getMonitor(uint32_t index)
{
	ASSERT((uint32_t)gMonitors.size() > index);
	return gMonitors[index];
}

float2 getMousePosition()
{
	POINT point;
	GetCursorPos(&point);
	return float2((float)point.x, (float)point.y);
}

bool getKeyDown(int key)
{
	return gKeys[key].down;
}

bool getKeyUp(int key)
{
	return gKeys[key].released;
}

bool getJoystickButtonDown(int button)
{
	// TODO: Implement gamepad / joystick support on windows
	return false;
}

bool getJoystickButtonUp(int button)
{
	// TODO: Implement gamepad / joystick support on windows
	return false;
}

/************************************************************************/
// Time Related Functions
/************************************************************************/
unsigned getSystemTime()
{
	return (unsigned)timeGetTime();
}

unsigned getTimeSinceStart()
{
	return (unsigned)time(NULL);
}

void sleep(unsigned mSec)
{
	::Sleep((DWORD)mSec);
}

static int64_t highResTimerFrequency = 0;

void initTime()
{
	LARGE_INTEGER frequency;
	if (QueryPerformanceFrequency(&frequency))
	{
		highResTimerFrequency = frequency.QuadPart;
	}
	else
	{
		highResTimerFrequency = 1000LL;
	}
}

// Make sure timer frequency is initialized before anyone tries to use it
struct StaticTime { StaticTime() { initTime(); } }staticTimeInst;

int64_t getUSec()
{
	LARGE_INTEGER counter;
	QueryPerformanceCounter(&counter);
	return counter.QuadPart;
}

int64_t getMSec()
{
	LARGE_INTEGER curr;
	QueryPerformanceCounter(&curr);
	return curr.QuadPart * (int64_t)1e3;
}

int64_t getTimerFrequency()
{
	if (highResTimerFrequency == 0)
		initTime();

	return highResTimerFrequency;
}

#endif
