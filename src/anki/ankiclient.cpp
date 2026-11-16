////////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2021 Ripose
//
// This file is part of Memento.
//
// Memento is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 2 of the License.
//
// Memento is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Memento.  If not, see <https://www.gnu.org/licenses/>.
//
////////////////////////////////////////////////////////////////////////////////

#include "anki/ankiclient.h"

#include <QClipboard>
#include <QDebug>
#include <QGuiApplication>
#include <QNetworkReply>
#include <QtConcurrent>

#ifdef MEMENTO_SYSTEM_QCORO
#include <QCoroFuture>
#include <QCoroNetworkReply>
#else
#include <qcoro/core/qcorofuture.h>
#include <qcoro/network/qcoronetworkreply.h>
#endif // MEMENTO_SYSTEM_QCORO

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

#include <QFile>
#include <QUrl>

#include "anki/ankiconnect.h"
#include "player/mpvcontroller.h"
#include "player/mpvplayer.h"
#include "state/context.h"
#include "subtitle/subtitlelistmodel.h"

/* The minimum AnkiConnect version required */
static constexpr int MIN_ANKICONNECT_VERSION = 6;

namespace Key
{

static constexpr const char *SUCCESS = "success";
static constexpr const char *ERROR = "error";
static constexpr const char *RESULT = "result";
static constexpr const char *DECKS = "decks";
static constexpr const char *MODELS = "models";
static constexpr const char *FIELDS = "fields";
static constexpr const char *EXPRESSION = "expression";
static constexpr const char *READING = "reading";
static constexpr const char *CHARACTER = "character";
static constexpr const char *ID = "id";
static constexpr const char *IDS = "ids";

} // namespace Key

namespace Error
{

static constexpr const char *NO_PROFILE_SET = "No Anki profile set";

} // namespace Error

/* Begin Constructor/Destructors */

AnkiClient::AnkiClient(Context *context, QObject *parent) :
    QObject(parent),
    m_context(context),
    m_manager(this),
    m_subtitleFilterRegex(m_context->settings()->searchRemoveRegex())
{
    constexpr int TIMEOUT = 5000;
    m_manager.setTransferTimeout(TIMEOUT);

    connect(
        m_context->settings(), &Settings::searchRemoveRegexChanged,
        this, &AnkiClient::updateSubtitleFilterRegex
    );
}

/* End Constructor/Destructors */
/* Begin Getters */

const AnkiProfile *AnkiClient::profile() const noexcept
{
    return m_context->ankiConfig()->profile();
}

/* End Getters */
/* Begin Slots */

void AnkiClient::updateSubtitleFilterRegex(const QString &filter)
{
    m_subtitleFilterRegex = QRegularExpression(filter);
}

/* End Slots */
/* Begin Commands */

QCoro::QmlTask AnkiClient::testConnection()
{
    return testConnectionAsync();
}

QCoro::Task<QVariantMap> AnkiClient::testConnectionAsync()
{
    QVariantMap result;

    if (profile() == nullptr)
    {
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    std::unique_ptr<QNetworkReply> reply =
        co_await makeRequest(profile(), AnkiConnect::Action::VERSION);

    QString error;
    QJsonObject replyObj = processReply(*reply, error);
    if (replyObj.isEmpty())
    {
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = std::move(error);
        co_return result;
    }

    if (!replyObj[AnkiConnect::Req::RESULT].isDouble())
    {
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("AnkiConnect result is not a number");
        co_return result;
    }

    if (replyObj[AnkiConnect::Req::RESULT].toInt() < MIN_ANKICONNECT_VERSION)
    {
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("AnkiConnect version %1 < %2").arg(
            QString::number(replyObj[AnkiConnect::Req::RESULT].toInt()),
            QString::number(MIN_ANKICONNECT_VERSION)
        );
        co_return result;
    }

    result[Key::SUCCESS] = true;
    co_return result;
}

QCoro::QmlTask AnkiClient::getDeckNames()
{
    return getDeckNamesAsync();
}

QCoro::Task<QVariantMap> AnkiClient::getDeckNamesAsync()
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    QVariantMap result =
        co_await requestStringList(profile(), AnkiConnect::Action::DECK_NAMES);
    if (!result[Key::SUCCESS].toBool())
    {
        co_return result;
    }

    QVariant decks = result.take(Key::RESULT);
    result[Key::DECKS] = std::move(decks);
    co_return result;
}

QCoro::QmlTask AnkiClient::getModelNames()
{
    return getModelNamesAsync();
}

QCoro::Task<QVariantMap> AnkiClient::getModelNamesAsync()
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    QVariantMap result =
        co_await requestStringList(profile(), AnkiConnect::Action::MODEL_NAMES);
    if (!result[Key::SUCCESS].toBool())
    {
        co_return result;
    }

    QVariant models = result.take(Key::RESULT);
    result[Key::MODELS] = std::move(models);
    co_return result;
}

QCoro::QmlTask AnkiClient::getFieldNames(const QString &model)
{
    return getFieldNamesAsync(model);
}

QCoro::Task<QVariantMap> AnkiClient::getFieldNamesAsync(const QString &model)
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    QJsonObject params;
    params[AnkiConnect::Param::MODEL_NAME] = model;
    QVariantMap result = co_await requestStringList(
        profile(), AnkiConnect::Action::FIELD_NAMES, std::move(params)
    );
    if (!result[Key::SUCCESS].toBool())
    {
        co_return result;
    }

    QVariant fields = result.take(Key::RESULT);
    result[Key::FIELDS] = std::move(fields);
    co_return result;
}

QCoro::QmlTask AnkiClient::noteAddable(const Term *term)
{
    return noteAddableAsync(term);
}

QCoro::Task<QVariantMap> AnkiClient::noteAddableAsync(const Term *term)
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    std::unique_ptr<AnkiProfile> profileCopy{profile()->clone(this)};
    std::unique_ptr<Term> termCopy{term->clone(this)};
    populate(termCopy.get());
    QJsonObject params = co_await QtConcurrent::run(
        [this, &profile = *profileCopy, &term = *termCopy] () -> QJsonObject
        {
            QJsonArray notes;

            term.setReadingAsExpression(false);
            Anki::Note::Context ctx = Anki::Note::build(
                *m_context, profile, term, false
            );
            notes.append(std::move(ctx.ankiObject));

            if (!term.reading().isEmpty())
            {
                term.setReadingAsExpression(true);
                ctx = Anki::Note::build(*m_context, profile, term, false);
                notes.append(std::move(ctx.ankiObject));
            }

            QJsonObject params;
            params[AnkiConnect::Note::CAN_ADD_NOTES_PARAM] = std::move(notes);
            return params;
        }
    );

    QVariantMap canAddResult = co_await requestBoolList(
        profileCopy.get(), AnkiConnect::Action::CAN_ADD_NOTES, std::move(params)
    );
    if (!canAddResult[Key::SUCCESS].toBool())
    {
        co_return canAddResult;
    }

    constexpr qsizetype EXPRESSION_INDEX = 0;
    constexpr qsizetype READING_INDEX = 1;
    QVariantList canAddList = canAddResult[Key::RESULT].toList();

    QVariantMap result;
    result[Key::SUCCESS] = true;
    result[Key::EXPRESSION] = EXPRESSION_INDEX < canAddList.size() &&
        canAddList[EXPRESSION_INDEX].toBool();
    result[Key::READING] = READING_INDEX < canAddList.size() &&
        canAddList[READING_INDEX].toBool();
    co_return result;
}

QCoro::QmlTask AnkiClient::noteAddable(const Kanji *kanji)
{
    return noteAddableAsync(kanji);
}

QCoro::Task<QVariantMap> AnkiClient::noteAddableAsync(const Kanji *kanji)
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    std::unique_ptr<AnkiProfile> profileCopy{profile()->clone(this)};
    std::unique_ptr<Kanji> kanjiCopy{kanji->clone(this)};
    populate(kanjiCopy.get());
    QJsonObject params = co_await QtConcurrent::run(
        [this, &profile = *profileCopy, &kanji = *kanjiCopy] () -> QJsonObject
        {
            QJsonArray notes;

            Anki::Note::Context ctx =
                Anki::Note::build(*m_context, profile, kanji, false);
            notes.append(std::move(ctx.ankiObject));

            QJsonObject params;
            params[AnkiConnect::Note::CAN_ADD_NOTES_PARAM] = notes;
            return params;
        }
    );

    QVariantMap canAddResult = co_await requestBoolList(
        profileCopy.get(), AnkiConnect::Action::CAN_ADD_NOTES, std::move(params)
    );
    if (!canAddResult[Key::SUCCESS].toBool())
    {
        co_return canAddResult;
    }

    constexpr qsizetype CHARACTER_INDEX = 0;
    QVariantList canAddList = canAddResult[Key::RESULT].toList();

    QVariantMap result;
    result[Key::SUCCESS] = true;
    result[Key::CHARACTER] = CHARACTER_INDEX < canAddList.size() &&
        canAddList[CHARACTER_INDEX].toBool();
    co_return result;
}

QCoro::QmlTask AnkiClient::addNote(const Term *term)
{
    return addNoteAsync(term);
}

QCoro::Task<QVariantMap> AnkiClient::addNoteAsync(const Term *term)
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    std::unique_ptr<AnkiProfile> profileCopy{profile()->clone(this)};
    std::unique_ptr<Term> termCopy{term->clone(this)};
    populate(termCopy.get());
    applyCardBuilderOverride(termCopy.get(), profileCopy.get());
    Anki::Note::Context ctx = co_await QtConcurrent::run(
        [this, &profile = *profileCopy, &term = *termCopy]
        () -> Anki::Note::Context
        {
            return Anki::Note::build(*m_context, profile, term, true);
        }
    );
    co_return co_await addNoteHelper(profileCopy.get(), std::move(ctx));
}

QCoro::QmlTask AnkiClient::addNote(const Kanji *kanji)
{
    return addNoteAsync(kanji);
}

QCoro::Task<QVariantMap> AnkiClient::addNoteAsync(const Kanji *kanji)
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    std::unique_ptr<AnkiProfile> profileCopy{profile()->clone(this)};
    std::unique_ptr<Kanji> kanjiCopy{kanji->clone(this)};
    populate(kanjiCopy.get());
    Anki::Note::Context ctx = co_await QtConcurrent::run(
        [this, &profile = *profileCopy, &kanji = *kanjiCopy]
        () -> Anki::Note::Context
        {
            return Anki::Note::build(*m_context, profile, kanji, true);
        }
    );
    co_return co_await addNoteHelper(profileCopy.get(), std::move(ctx));
}

QCoro::Task<QVariantMap> AnkiClient::addNoteHelper(
    const AnkiProfile *profile, Anki::Note::Context &&ctx)
{
    if (!ctx.fileMap.isEmpty())
    {
        QVariantMap addMediaResult =
            co_await addMedia(profile, std::move(ctx.fileMap));
        if (!addMediaResult[Key::SUCCESS].toBool())
        {
            co_return addMediaResult;
        }
    }

    QJsonObject params;
    params[AnkiConnect::Param::ADD_NOTE] = std::move(ctx.ankiObject);
    QVariantMap addNoteResult = co_await requestInt(
        profile, AnkiConnect::Action::ADD_NOTE, std::move(params)
    );
    if (!addNoteResult[Key::SUCCESS].toBool())
    {
        co_return addNoteResult;
    }

    QVariantMap result;
    result[Key::SUCCESS] = true;
    result[Key::ID] = addNoteResult[Key::RESULT].toInt();
    co_return result;
}

QCoro::Task<QVariantMap> AnkiClient::addMedia(
    const AnkiProfile *profile, QList<GlossaryBuilder::FileInfo> fileMap)
{
    QJsonArray actions;
    for (const GlossaryBuilder::FileInfo &info : fileMap)
    {
        QJsonObject command;
        command[AnkiConnect::Req::ACTION] =
            AnkiConnect::Action::STORE_MEDIA_FILE;
        QJsonObject fileParams;
        fileParams[AnkiConnect::Note::DATA] = FileUtils::toBase64(info.path);
        fileParams[AnkiConnect::Note::FILENAME] = info.name;
        command[AnkiConnect::Req::PARAMS] = fileParams;

        actions.append(std::move(command));
    }

    QJsonObject params;
    params[AnkiConnect::Param::ACTIONS] = std::move(actions);
    std::unique_ptr<QNetworkReply> reply = co_await makeRequest(
        profile, AnkiConnect::Action::MULTI, std::move(params)
    );

    QString error;
    QJsonObject multiResult = processReply(*reply, error);
    if (!error.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = std::move(error);
        co_return result;
    }
    else if (multiResult.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = true;
        result[Key::RESULT] = QStringList{};
        co_return result;
    }
    else if (!multiResult[AnkiConnect::Req::RESULT].isArray())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("Result is not an array");
        co_return result;
    }

    QStringList filenames;
    QJsonArray actionResults = multiResult[AnkiConnect::Req::RESULT].toArray();
    for (QJsonValueRef actionResult : actionResults)
    {
        if (!actionResult.isString())
        {
            QVariantMap result;
            result[Key::SUCCESS] = false;
            result[Key::ERROR] = tr("Result is not a string");
            co_return result;
        }
        filenames.emplaceBack(actionResult.toString());
    }

    QVariantMap result;
    result[Key::SUCCESS] = true;
    result[Key::RESULT] = std::move(filenames);
    co_return result;
}

QCoro::QmlTask AnkiClient::openBrowse(const QString &deck, const QString &query)
{
    return openBrowseAsync(deck, query);
}

QCoro::Task<QVariantMap> AnkiClient::openBrowseAsync(
    const QString &deck, const QString &query)
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    QJsonObject params;
    QString queryStr;
    switch (profile()->duplicatePolicy())
    {
        case Anki::DuplicatePolicyDifferentDeck:
        case Anki::DuplicatePolicySameDeck:
            queryStr += "\"deck:" + deck + "\" ";
            [[fallthrough]];

        case Anki::DuplicatePolicyNone:
        default:
            queryStr += '(';
            queryStr += query;
            queryStr += ')';
            break;
    }
    params[AnkiConnect::Param::QUERY] = std::move(queryStr);
    std::unique_ptr<QNetworkReply> reply = co_await makeRequest(
        profile(), AnkiConnect::Action::GUI_BROWSE, params
    );

    QString error;
    QJsonObject replyObj = processReply(*reply, error);
    if (!error.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = std::move(error);
        co_return result;
    }
    else if (replyObj.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = true;
        result[Key::IDS] = QVariantList{};
        co_return result;
    }
    else if (!replyObj[AnkiConnect::Req::RESULT].isArray())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("Result is not an array");
        co_return result;
    }

    QVariantList ids;
    QJsonArray resultArray = replyObj[AnkiConnect::Req::RESULT].toArray();
    for (QJsonValueRef addable : resultArray)
    {
        if (!addable.isDouble())
        {
            QVariantMap result;
            result[Key::SUCCESS] = false;
            result[Key::ERROR] = tr("Response was not an array of bool");
            co_return result;
        }
        ids.emplaceBack(addable.toInt());
    }

    QVariantMap result;
    result[Key::SUCCESS] = true;
    result[Key::RESULT] = std::move(ids);
    co_return result;
}

QCoro::QmlTask AnkiClient::openDuplicates(const Term *term)
{
    return openDuplicatesAsync(term);
}

QCoro::Task<QVariantMap> AnkiClient::openDuplicatesAsync(const Term *term)
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    std::unique_ptr<AnkiProfile> profileCopy{profile()->clone(this)};
    std::unique_ptr<Term> termCopy{term->clone(this)};

    QVariantMap fieldNamesResult =
        co_await getFieldNamesAsync(profileCopy->termModel());
    if (!fieldNamesResult[Key::SUCCESS].toBool())
    {
        co_return fieldNamesResult;
    }

    QStringList fieldNames = fieldNamesResult[Key::FIELDS].toStringList();
    if (fieldNames.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("The current model has no fields");
        co_return result;
    }
    QString fieldKey = fieldNames.front();

    termCopy->setReadingAsExpression(false);
    Anki::Note::Context ctx = co_await QtConcurrent::run(
        [this, &profile = *profileCopy, &term = *termCopy]
        () -> Anki::Note::Context
        {
            return Anki::Note::build(*m_context, profile, term, false);
        }
    );
    QString fieldValue =
        ctx.ankiObject[AnkiConnect::Note::FIELDS][fieldKey].toString();

    QString query = QString("%1:\"%2\"")
        .arg(fieldKey)
        .arg(fieldValue.replace('\\', "\\\\").replace('"', "\\\""));

    if (!termCopy->reading().isEmpty())
    {
        termCopy->setReadingAsExpression(true);
        ctx = co_await QtConcurrent::run(
            [this, &profile = *profileCopy, &term = *termCopy]
            () -> Anki::Note::Context
            {
                return Anki::Note::build(*m_context, profile, term, false);
            }
        );
        QString fieldValue =
            ctx.ankiObject[AnkiConnect::Note::FIELDS][fieldKey].toString();

        query += QString(" OR %1:\"%2\"")
            .arg(fieldKey)
            .arg(fieldValue.replace('\\', "\\\\").replace('"', "\\\""));
    }

    co_return co_await openBrowseAsync(profileCopy->termDeck(), query);
}

QCoro::QmlTask AnkiClient::openDuplicates(const Kanji *kanji)
{
    return openDuplicatesAsync(kanji);
}

QCoro::Task<QVariantMap> AnkiClient::openDuplicatesAsync(const Kanji *kanji)
{
    if (profile() == nullptr)
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr(Error::NO_PROFILE_SET);
        co_return result;
    }

    std::unique_ptr<AnkiProfile> profileCopy{profile()->clone(this)};
    std::unique_ptr<Kanji> kanjiCopy{kanji->clone(this)};

    QVariantMap fieldNamesResult =
        co_await getFieldNamesAsync(profileCopy->termModel());
    if (!fieldNamesResult[Key::SUCCESS].toBool())
    {
        co_return fieldNamesResult;
    }

    QStringList fieldNames = fieldNamesResult[Key::FIELDS].toStringList();
    if (fieldNames.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("The current model has no fields");
        co_return result;
    }
    QString fieldKey = fieldNames.front();

    Anki::Note::Context ctx = co_await QtConcurrent::run(
        [this, &profile = *profileCopy, &kanji = *kanjiCopy]
        () -> Anki::Note::Context
        {
            return Anki::Note::build(*m_context, profile, kanji, false);
        }
    );
    QString fieldValue =
        ctx.ankiObject[AnkiConnect::Note::FIELDS][fieldKey].toString();

    QString query = QString("%1:\"%2\"")
        .arg(fieldKey)
        .arg(fieldValue.replace('\\', "\\\\").replace('"', "\\\""));

    co_return co_await openBrowseAsync(profileCopy->kanjiDeck(), query);
}

/* End Commands */
/* Begin Network Helpers */

QCoro::Task<QVariantMap> AnkiClient::requestStringList(
    const AnkiProfile *profile,
    const QString &action,
    const QJsonObject &params)
{
    std::unique_ptr<QNetworkReply> reply =
        co_await makeRequest(profile, action, params);

    QString error;
    QJsonObject replyObj = processReply(*reply, error);
    if (!error.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = std::move(error);
        co_return result;
    }
    else if (replyObj.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = true;
        result[Key::RESULT] = QStringList{};
        co_return result;
    }
    else if (!replyObj[AnkiConnect::Req::RESULT].isArray())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("Result is not an array");
        co_return result;
    }

    QStringList values;
    QJsonArray resultArray = replyObj[AnkiConnect::Req::RESULT].toArray();
    for (const QJsonValueRef string : resultArray)
    {
        if (!string.isString())
        {
            QVariantMap result;
            result[Key::SUCCESS] = false;
            result[Key::ERROR] = tr("Response was not an array of strings");
        }
        values.emplaceBack(string.toString());
    }

    QVariantMap result;
    result[Key::SUCCESS] = true;
    result[Key::RESULT] = std::move(values);
    co_return result;
}

QCoro::Task<QVariantMap> AnkiClient::requestBoolList(
    const AnkiProfile *profile,
    const QString &action,
    const QJsonObject &params)
{
    std::unique_ptr<QNetworkReply> reply =
        co_await makeRequest(profile, action, params);

    QString error;
    QJsonObject replyObj = processReply(*reply, error);
    if (!error.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = std::move(error);
        co_return result;
    }
    else if (replyObj.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = true;
        result[Key::RESULT] = QVariantList{};
        co_return result;
    }
    else if (!replyObj[AnkiConnect::Req::RESULT].isArray())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("Result is not an array");
        co_return result;
    }

    QVariantList values;
    QJsonArray resultArray = replyObj[AnkiConnect::Req::RESULT].toArray();
    for (QJsonValueRef boolean : resultArray)
    {
        if (!boolean.isBool())
        {
            QVariantMap result;
            result[Key::SUCCESS] = false;
            result[Key::ERROR] = tr("Response was not an array of bool");
            co_return result;
        }
        values.emplaceBack(boolean.toBool());
    }

    QVariantMap result;
    result[Key::SUCCESS] = true;
    result[Key::RESULT] = std::move(values);
    co_return result;
}

QCoro::Task<QVariantMap> AnkiClient::requestInt(
    const AnkiProfile *profile,
    const QString &action,
    const QJsonObject &params)
{
    std::unique_ptr<QNetworkReply> reply =
        co_await makeRequest(profile, action, params);

    QString error;
    QJsonObject replyObj = processReply(*reply, error);
    if (!error.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = std::move(error);
        co_return result;
    }
    else if (replyObj.isEmpty())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("AnkiConnect result was an empty value");
        co_return result;
    }

    if (!replyObj[AnkiConnect::Req::RESULT].isDouble())
    {
        QVariantMap result;
        result[Key::SUCCESS] = false;
        result[Key::ERROR] = tr("AnkiConnect result is not a double");
        co_return result;
    }

    QVariantMap result;
    result[Key::SUCCESS] = true;
    result[Key::RESULT] = replyObj[AnkiConnect::Req::RESULT].toInt();
    co_return result;
}

QCoro::Task<std::unique_ptr<QNetworkReply>> AnkiClient::makeRequest(
    const AnkiProfile *profile,
    const QString &action,
    const QJsonObject &params)
{
    QNetworkRequest request;
    request.setUrl(QUrl(
        QString("%1:%2")
            .arg(profile->hostname())
            .arg(profile->port())
    ));
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject jsonMsg;
    jsonMsg[AnkiConnect::Req::ACTION] = action;
    jsonMsg[AnkiConnect::Req::VERSION] = MIN_ANKICONNECT_VERSION;
    if (profile->useApiKey())
    {
        jsonMsg[AnkiConnect::Req::KEY] = profile->apiKey();
    }
    if (!params.isEmpty())
    {
        jsonMsg[AnkiConnect::Req::PARAMS] = params;
    }
    QJsonDocument jsonDoc(jsonMsg);

    co_return std::unique_ptr<QNetworkReply>{
        co_await m_manager.post(request, jsonDoc.toJson())
    };
}

QJsonObject AnkiClient::processReply(QNetworkReply &reply, QString &error)
{
    switch (reply.error())
    {
        case QNetworkReply::NoError:
        {
            QJsonDocument replyDoc = QJsonDocument::fromJson(reply.readAll());
            if (replyDoc.isNull())
            {
                error = tr("Reply was not JSON");
                qDebug() << reply.readAll();
                return {};
            }
            else if (!replyDoc.isObject())
            {
                error = tr("Reply was not an object");
                return {};
            }

            QJsonObject replyObj = replyDoc.object();
            if (replyObj.length() != 2)
            {
                error = tr("Anki response has unexpected number of fields");
            }
            else if (!replyObj.contains(AnkiConnect::Reply::ERROR))
            {
                error = tr("Anki response is missing error field");
            }
            else if (!replyObj.contains(AnkiConnect::Req::RESULT))
            {
                error = tr("Anki response is missing result field");
            }
            else if (!replyObj[AnkiConnect::Reply::ERROR].isNull())
            {
                error = replyObj[AnkiConnect::Reply::ERROR].toString();
            }
            else
            {
                return replyObj;
            }
            break;
        }

        default:
            error = reply.errorString();
            break;
    }

    return {};
}

/* End Network Helpers */
/* Begin Expression Helpers */

void AnkiClient::populate(Expression *expression) const
{
    MpvState *state = m_context->player()->state();
    expression->setTitle(state->title());
    QString subtitleText = state->subtitle()->text();
    expression->setSubtitle(subtitleText.remove(m_subtitleFilterRegex));
    expression->setStartTime(
        state->subtitle()->startTime() + state->subtitle()->delay()
    );
    expression->setEndTime(
        state->subtitle()->endTime() + state->subtitle()->delay()
    );
    expression->setSubtitle2(state->secondarySubtitle()->text());

    /* Set {context} fields */
    const SubtitleListModel *primaryList =
        m_context->subtitleLists()->primary();
    if (primaryList != nullptr)
    {
        const std::vector<SubtitleEntry> &primaryListItems =
            primaryList->items();
        QModelIndexList primarySelection =
            primaryList->selectionModel()->selectedIndexes();
        std::ranges::sort(
            primarySelection,
            [] (const QModelIndex &lhs, const QModelIndex &rhs) -> bool
            {
                return lhs.row() < rhs.row();
            }
        );
        QStringList contextList;
        double contextEndTime = 0;
        for (const QModelIndex &index : primarySelection)
        {
            QString text = primaryListItems[index.row()].text;
            text.remove(m_subtitleFilterRegex);
            if (text.isEmpty())
            {
                continue;
            }
            contextList.emplaceBack(std::move(text));
            contextEndTime = std::max(
                contextEndTime, primaryListItems[index.row()].end
            );
        }
        if (!contextList.isEmpty())
        {
            expression->setContextStartTime(
                primaryListItems[primarySelection.front().row()].start +
                    state->subtitle()->delay()
            );
            expression->setContextEndTime(
                contextEndTime + state->subtitle()->delay()
            );
            expression->setContext(contextList.join('\n'));
        }
    }

    /* Set {context-2} */
    const SubtitleListModel *secondaryList =
        m_context->subtitleLists()->secondary();
    if (secondaryList != nullptr)
    {
        const std::vector<SubtitleEntry> &secondaryListItems =
            secondaryList->items();
        QModelIndexList secondarySelection =
            secondaryList->selectionModel()->selectedIndexes();
        std::ranges::sort(
            secondarySelection,
            [] (const QModelIndex &lhs, const QModelIndex &rhs) -> bool
            {
                return lhs.row() < rhs.row();
            }
        );
        QStringList context2List;
        for (const QModelIndex &index : secondarySelection)
        {
            QString text = secondaryListItems[index.row()].text;
            if (text.isEmpty())
            {
                continue;
            }
            context2List.emplaceBack(std::move(text));
        }
        if (!context2List.isEmpty())
        {
            expression->setContext2(context2List.join('\n'));
        }
    }

    expression->setClipboard(QGuiApplication::clipboard()->text());
}

/* End Expression Helpers */

/* Begin Card Builder */

/**
 * Reads a PCM WAV file and returns `bins` bars (0 to 1) of its loudness.
 */
static QVariantList wavPeaks(const QString &path, int bins, double &duration)
{
    duration = 0;
    QFile file{path};
    if (bins <= 0 || !file.open(QIODevice::ReadOnly))
    {
        return {};
    }
    const QByteArray d = file.readAll();
    if (d.size() < 44 || !d.startsWith("RIFF"))
    {
        return {};
    }

    auto u16 = [&d] (qsizetype p) -> quint32
    {
        return quint32(uchar(d[p])) | (quint32(uchar(d[p + 1])) << 8);
    };
    auto u32 = [&u16] (qsizetype p) -> quint32
    {
        return u16(p) | (u16(p + 2) << 16);
    };

    quint32 tag = 1;
    quint32 channels = 1;
    quint32 rate = 48000;
    quint32 bits = 16;
    qsizetype dataPos = -1;
    qsizetype dataSize = 0;
    qsizetype pos = 12;
    while (pos + 8 <= d.size())
    {
        const QByteArray id = d.mid(pos, 4);
        const quint32 size = u32(pos + 4);
        pos += 8;
        if (id == "fmt " && pos + 16 <= d.size())
        {
            tag = u16(pos);
            channels = u16(pos + 2);
            rate = u32(pos + 4);
            bits = u16(pos + 14);
            if (tag == 0xFFFE && size >= 26 && pos + 26 <= d.size())
            {
                tag = u16(pos + 24);
            }
        }
        else if (id == "data")
        {
            const qsizetype rest = d.size() - pos;
            dataPos = pos;
            dataSize = (size == 0 || qsizetype(size) > rest) ? rest : qsizetype(size);
            break;
        }
        pos += qsizetype(size) + (size & 1);
    }

    const quint32 bytesPerSample = bits / 8;
    if (dataPos < 0 || channels == 0 || rate == 0 ||
        (bytesPerSample != 1 && bytesPerSample != 2 &&
         bytesPerSample != 3 && bytesPerSample != 4))
    {
        return {};
    }
    const qsizetype frameSize = qsizetype(channels) * bytesPerSample;
    const qsizetype frames = dataSize / frameSize;
    if (frames <= 0)
    {
        return {};
    }
    duration = double(frames) / rate;

    auto sampleAt = [&] (qsizetype frame, quint32 channel) -> double
    {
        const qsizetype p =
            dataPos + frame * frameSize + qsizetype(channel) * bytesPerSample;
        switch (bytesPerSample)
        {
            case 1:
                return (int(uchar(d[p])) - 128) / 128.0;
            case 2:
                return qint16(u16(p)) / 32768.0;
            case 3:
            {
                qint32 v = qint32(u16(p) | (quint32(uchar(d[p + 2])) << 16));
                if (v & 0x800000)
                {
                    v -= 0x1000000;
                }
                return v / 8388608.0;
            }
            default:
            {
                const quint32 raw = u32(p);
                if (tag == 3)
                {
                    float f;
                    memcpy(&f, &raw, sizeof(f));
                    return f;
                }
                return qint32(raw) / 2147483648.0;
            }
        }
    };

    std::vector<double> peaks(bins, 0.0);
    double maxPeak = 0;
    for (int b = 0; b < bins; ++b)
    {
        const qsizetype from = frames * b / bins;
        const qsizetype to =
            std::max<qsizetype>(from + 1, frames * (b + 1) / bins);
        const qsizetype step = std::max<qsizetype>(1, (to - from) / 64);
        double peak = 0;
        for (qsizetype f = from; f < to && f < frames; f += step)
        {
            for (quint32 c = 0; c < channels; ++c)
            {
                peak = std::max(peak, std::abs(sampleAt(f, c)));
            }
        }
        peaks[b] = peak;
        maxPeak = std::max(maxPeak, peak);
    }

    QVariantList result;
    result.reserve(bins);
    for (double p : peaks)
    {
        result.append(maxPeak > 1e-4 ? p / maxPeak : 0.0);
    }
    return result;
}

QVariantMap AnkiClient::cardBuilderStart() const
{
    QVariantMap result;
    result["available"] = false;
    if (profile() != nullptr)
    {
        result["padStart"] = profile()->audioPadStart();
        result["padEnd"] = profile()->audioPadEnd();
    }

    const SubtitleListModel *list = m_context->subtitleLists()->primary();
    const MpvSubtitle *sub = m_context->player()->state()->subtitle();
    if (list == nullptr || sub->text().isEmpty())
    {
        return result;
    }
    const std::vector<SubtitleEntry> &items = list->items();
    result["count"] = int(items.size());

    /* The current line: the list entry that best matches what is showing */
    int current = -1;
    double bestDistance = 0.05;
    for (size_t i = 0; i < items.size(); ++i)
    {
        const double distance = std::abs(items[i].start - sub->startTime()) +
            std::abs(items[i].end - sub->endTime());
        if (distance < bestDistance)
        {
            bestDistance = distance;
            current = int(i);
        }
    }

    /* Lines selected by hand in the subtitle list win over the current one */
    int first = -1;
    int last = -1;
    const QModelIndexList selection =
        list->selectionModel()->selectedIndexes();
    for (const QModelIndex &index : selection)
    {
        if (index.row() < 0 || size_t(index.row()) >= items.size())
        {
            continue;
        }
        first = first < 0 ? index.row() : std::min(first, index.row());
        last = std::max(last, index.row());
    }
    if (first < 0 || (current >= 0 && (current < first || current > last)))
    {
        first = last = current;
    }
    if (first < 0)
    {
        return result;
    }

    result["available"] = true;
    result["first"] = first;
    result["last"] = last;
    return result;
}

QVariantMap AnkiClient::cardBuilderLine(int row) const
{
    QVariantMap result;
    const SubtitleListModel *list = m_context->subtitleLists()->primary();
    if (list == nullptr || row < 0 || size_t(row) >= list->items().size())
    {
        return result;
    }
    const SubtitleEntry &entry = list->items()[row];
    const double delay = m_context->player()->state()->subtitle()->delay();
    QString text = entry.text;
    text.remove(m_subtitleFilterRegex);
    result["text"] = text;
    result["start"] = entry.start + delay;
    result["end"] = entry.end + delay;
    return result;
}

QCoro::QmlTask AnkiClient::cardBuilderClip(double start, double end, int bins)
{
    return cardBuilderClipAsync(start, end, bins);
}

QCoro::Task<QVariantMap> AnkiClient::cardBuilderClipAsync(
    double start, double end, int bins)
{
    start = std::max(0.0, start);
    QVariantMap failed;
    failed["success"] = false;
    if (end <= start)
    {
        co_return failed;
    }

    MpvController *controller = m_context->player()->controller();
    QVariantMap clip = co_await QtConcurrent::run(
        [controller, start, end, bins] () -> QVariantMap
        {
            MpvAudioClipArgs args{};
            args.start = start;
            args.end = end;
            args.normalize = false;
            args.extension = ".wav";
            const QString path = controller->tempAudioClip(args);

            QVariantMap out;
            out["success"] = false;
            if (path.isEmpty())
            {
                return out;
            }
            double duration = 0;
            out["path"] = path;
            out["peaks"] = wavPeaks(path, bins, duration);
            out["duration"] = duration;
            out["success"] = duration > 0;
            return out;
        }
    );

    if (clip.contains("path"))
    {
        m_cardClips.append(clip["path"].toString());
        clip["url"] = QUrl::fromLocalFile(clip["path"].toString()).toString();
    }
    clip["start"] = start;
    co_return clip;
}

void AnkiClient::setCardBuilderOverride(
    const QString &text, double start, double end)
{
    m_cardOverride = {true, text, start, end};
}

void AnkiClient::clearCardBuilderOverride()
{
    m_cardOverride = {};
    for (const QString &path : std::as_const(m_cardClips))
    {
        QFile::remove(path);
    }
    m_cardClips.clear();
}

void AnkiClient::applyCardBuilderOverride(
    Term *term, const AnkiProfile *profile)
{
    if (!m_cardOverride.active)
    {
        return;
    }
    const CardBuilderOverride o = m_cardOverride;
    m_cardOverride = {};

    term->setStartTime(o.start + profile->audioPadStart());
    term->setEndTime(o.end - profile->audioPadEnd());

    /* Keep the cloze markers around the word inside the longer sentence */
    const QString original =
        term->clozePrefix() + term->clozeBody() + term->clozeSuffix();
    qsizetype at = original.isEmpty() ? -1 : o.text.indexOf(original);
    if (at >= 0)
    {
        term->setClozePrefix(o.text.left(at) + term->clozePrefix());
        term->setClozeSuffix(
            term->clozeSuffix() + o.text.mid(at + original.size())
        );
    }
    else
    {
        const QString body = term->clozeBody();
        at = body.isEmpty() ? -1 : o.text.indexOf(body);
        if (at >= 0)
        {
            term->setClozePrefix(o.text.left(at));
            term->setClozeSuffix(o.text.mid(at + body.size()));
        }
        else
        {
            term->setClozePrefix(o.text);
            term->setClozeBody({});
            term->setClozeSuffix({});
        }
    }
    term->setSubtitle(o.text);
}

/* End Card Builder */
