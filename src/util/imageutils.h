////////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2026 Ripose
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

#pragma once

#include <QString>
#include <QStringList>

/**
 * @brief Utilities for handling imagery.
 */
namespace ImageUtils
{

/**
 * @brief Resize the image using extended marker syntax options
 *
 * @param filePath The file path where the screenshot was saved.
 * @param ext The file extension.
 * @param newWidth The desired new image width.
 * @param newHeight The desired new image width.
 * @param keepAspectRatio Whether or not to maintain the image aspect ratio.
 * @return Path of the new resized image if successful, else an empty string.
 */
[[nodiscard]]
QString resizeImage(
    const QString &path,
    const QString &ext,
    int newWidth,
    int newHeight,
    bool keepAspectRatio = true);


/**
 * @brief Generates a pitch graph SVG.
 *
 * @param moraSize The number of mora.
 * @param pos The pitch position number.
 * @param fill The fill color of the graph.
 * @param stroke The stroke color of the graph.
 * @return The string representation of the SVG.
 */
[[nodiscard]]
QString generatePitchGraph(
    const int moraSize,
    const uint8_t pos,
    const QString &fill,
    const QString &stroke);

/**
 * @brief Generates a Yomitan-style pitch graph SVG (fork): small dots, thin
 * lines, the kana of each mora under its dot, a hollow dot for the particle
 * and a ringed dot on the last high mora before a downstep.
 *
 * @param mora The mora of the reading, one string each.
 * @param pos The pitch position number (0 = heiban).
 * @param stroke The colour of dots, lines and kana.
 * @return The string representation of the SVG.
 */
[[nodiscard]]
QString generatePitchGraphYomitan(
    const QStringList &mora,
    const uint8_t pos,
    const QString &stroke);

} // namespace ImageUtils
