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
/* Same layout as XINPUT_STATE in xinput.h */
struct PadState
{
    quint32 packet;
    quint16 buttons;
    quint8 leftTrigger;
    quint8 rightTrigger;
    qint16 lx, ly, rx, ry;
};

typedef quint32 (__stdcall *GetStateFn)(quint32, PadState *);

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
