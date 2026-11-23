#include "gamepad.h"

#include <QDateTime>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQuickItem>
#include <QQuickWindow>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace
{
constexpr int STICK_DEADZONE = 8000;      /* of 32767 */
constexpr double CURSOR_MAX_SPEED = 22.0;  /* pixels per poll at full tilt */
constexpr double WHEEL_MAX = 40.0;         /* wheel units per poll (120 = one notch) */
constexpr int TRIGGER_DOWN = 120;          /* of 255 */
constexpr int TRIGGER_UP = 60;
}

/* Same layout as XINPUT_STATE in xinput.h */
struct PadState
{
    quint32 packet;
    quint16 buttons;
    quint8 leftTrigger;
    quint8 rightTrigger;
    qint16 lx, ly, rx, ry;
};

namespace
{
typedef quint32 (__stdcall *GetStateFn)(quint32, PadState *);

/* -1..1 past the dead zone, curved so small tilts are precise */
double stickValue(int raw)
{
    const int a = raw < 0 ? -raw : raw;
    if (a <= STICK_DEADZONE)
    {
        return 0;
    }
    const double v = double(a - STICK_DEADZONE) / double(32767 - STICK_DEADZONE);
    const double curved = v * v;
    return raw < 0 ? -curved : curved;
}

#ifdef Q_OS_WIN
void sendMouse(DWORD flags, int wheel = 0)
{
    INPUT input{};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = flags;
    input.mi.mouseData = static_cast<DWORD>(wheel);
    SendInput(1, &input, sizeof(INPUT));
}
#endif

constexpr int FAST_MS = 30;    /* while a controller is connected */
constexpr int SLOW_MS = 1000;  /* looking for one */
constexpr qint64 REPEAT_DELAY_MS = 400;
constexpr qint64 REPEAT_EVERY_MS = 150;

struct Button
{
    quint16 mask;
    const char *name;
};

constexpr Button BUTTONS[] = {
    {0x0001, "up"},
    {0x0002, "down"},
    {0x0004, "left"},
    {0x0008, "right"},
    {0x0010, "start"},
    {0x0020, "back"},
    {0x0100, "lb"},
    {0x0200, "rb"},
    {0x1000, "a"},
    {0x2000, "b"},
    {0x4000, "x"},
    {0x8000, "y"},
};

constexpr quint16 REPEATING = 0x000F; /* D-pad */
}

Gamepad::Gamepad(QObject *parent) : QObject(parent)
{
#ifdef Q_OS_WIN
    HMODULE lib = LoadLibraryW(L"xinput1_4.dll");
    if (!lib)
    {
        lib = LoadLibraryW(L"xinput9_1_0.dll");
    }
    if (lib)
    {
        m_getState = reinterpret_cast<void *>(GetProcAddress(lib, "XInputGetState"));
    }
#endif
    if (!m_getState)
    {
        return;
    }
    connect(&m_timer, &QTimer::timeout, this, &Gamepad::poll);
    m_timer.start(SLOW_MS);
}

void Gamepad::poll()
{
    GetStateFn getState = reinterpret_cast<GetStateFn>(m_getState);
    PadState state{};
    bool found = false;

    /* Stick to the slot that answered last; otherwise look at all four */
    if (m_slot >= 0 && getState(m_slot, &state) == 0)
    {
        found = true;
    }
    else
    {
        m_slot = -1;
        for (int i = 0; i < 4; ++i)
        {
            if (getState(i, &state) == 0)
            {
                m_slot = i;
                found = true;
                break;
            }
        }
    }

    if (!found)
    {
        m_lastButtons = 0;
        if (m_timer.interval() != SLOW_MS)
        {
            m_timer.setInterval(SLOW_MS);
        }
        return;
    }
    if (m_timer.interval() != FAST_MS)
    {
        m_timer.setInterval(FAST_MS);
    }

    if (QGuiApplication::applicationState() == Qt::ApplicationActive)
    {
        moveMouse(state);
    }

    const quint16 buttons = state.buttons;
    const quint16 pressed = buttons & ~m_lastButtons;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const bool active =
        QGuiApplication::applicationState() == Qt::ApplicationActive;

    if (pressed & REPEATING)
    {
        m_heldSince = now;
        m_lastRepeat = now;
    }

    for (const Button &b : BUTTONS)
    {
        if (!active)
        {
            break;
        }
        if (pressed & b.mask)
        {
            Q_EMIT buttonPressed(QString::fromLatin1(b.name));
        }
        else if ((buttons & b.mask & REPEATING) &&
                 now - m_heldSince >= REPEAT_DELAY_MS &&
                 now - m_lastRepeat >= REPEAT_EVERY_MS)
        {
            Q_EMIT buttonPressed(QString::fromLatin1(b.name));
            m_lastRepeat = now;
        }
    }
    m_lastButtons = buttons;
}

void Gamepad::click(QObject *object)
{
    QQuickItem *item = qobject_cast<QQuickItem *>(object);
    if (!item || !item->window())
    {
        return;
    }
    QQuickWindow *window = item->window();
    const QPointF scene = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
    const QPointF global = window->mapToGlobal(scene);
    QMouseEvent press(QEvent::MouseButtonPress, scene, global,
                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &press);
    QMouseEvent release(QEvent::MouseButtonRelease, scene, global,
                        Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &release);
}

void Gamepad::key(int key)
{
    QWindow *window = QGuiApplication::focusWindow();
    if (!window)
    {
        return;
    }
    QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &press);
    QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &release);
}

/* Left stick = mouse cursor, RT = left click (held = drag), LT = right
 * click, right stick = scroll. Real mouse input, so hovering subtitles
 * opens the lookup popup as with the mouse. */
void Gamepad::moveMouse(const PadState &state)
{
#ifdef Q_OS_WIN
    const double dx = stickValue(state.lx) * CURSOR_MAX_SPEED;
    const double dy = -stickValue(state.ly) * CURSOR_MAX_SPEED;
    if (dx != 0 || dy != 0)
    {
        m_moveX += dx;
        m_moveY += dy;
        const int stepX = static_cast<int>(m_moveX);
        const int stepY = static_cast<int>(m_moveY);
        if (stepX != 0 || stepY != 0)
        {
            m_moveX -= stepX;
            m_moveY -= stepY;
            POINT p;
            if (GetCursorPos(&p))
            {
                SetCursorPos(p.x + stepX, p.y + stepY);
            }
        }
    }
    else
    {
        m_moveX = 0;
        m_moveY = 0;
    }

    const double wheel = stickValue(state.ry) * WHEEL_MAX;
    if (wheel != 0)
    {
        m_wheel += wheel;
        const int step = static_cast<int>(m_wheel);
        if (step >= 15 || step <= -15)
        {
            m_wheel -= step;
            sendMouse(MOUSEEVENTF_WHEEL, step);
        }
    }
    else
    {
        m_wheel = 0;
    }

    if (!m_leftDown && state.rightTrigger >= TRIGGER_DOWN)
    {
        m_leftDown = true;
        sendMouse(MOUSEEVENTF_LEFTDOWN);
    }
    else if (m_leftDown && state.rightTrigger <= TRIGGER_UP)
    {
        m_leftDown = false;
        sendMouse(MOUSEEVENTF_LEFTUP);
    }
    if (!m_rightDown && state.leftTrigger >= TRIGGER_DOWN)
    {
        m_rightDown = true;
        sendMouse(MOUSEEVENTF_RIGHTDOWN);
    }
    else if (m_rightDown && state.leftTrigger <= TRIGGER_UP)
    {
        m_rightDown = false;
        sendMouse(MOUSEEVENTF_RIGHTUP);
    }
#else
    Q_UNUSED(state);
#endif
}
