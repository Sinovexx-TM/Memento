#ifndef GAMEPAD_H
#define GAMEPAD_H

#include <QObject>
#include <QString>
#include <QTimer>

/**
 * @brief Reads an Xbox-style (XInput) controller on Windows and emits a
 *        signal for each button press. Does nothing on other systems.
 *
 * xinput1_4.dll is loaded at run time, so there is no link dependency.
 * Presses are only reported while Memento is the active window.
 */
class Gamepad : public QObject
{
    Q_OBJECT

public:
    explicit Gamepad(QObject *parent = nullptr);

    /**
     * @brief Left-click the middle of a QML item, as the mouse would.
     */
    Q_INVOKABLE void click(QObject *item);

    /**
     * @brief Press and release a key in the focused window.
     */
    Q_INVOKABLE void key(int key);

Q_SIGNALS:
    /**
     * @brief A button was pressed (or a D-pad direction is held and repeats).
     * @param name "a", "b", "x", "y", "lb", "rb", "start", "back",
     *             "up", "down", "left", "right".
     */
    void buttonPressed(const QString &name);

private:
    void poll();

    QTimer m_timer;
    void *m_getState = nullptr;
    quint16 m_lastButtons = 0;
    int m_slot = -1;
    qint64 m_heldSince = 0;
    qint64 m_lastRepeat = 0;
};

#endif // GAMEPAD_H
