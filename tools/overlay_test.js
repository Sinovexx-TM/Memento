// Tests for overlay/app/layout.js: deno run --allow-read tools/overlay_test.js
const src = Deno.readTextFileSync(new URL("../overlay/app/layout.js", import.meta.url));
const { splitChars, layoutBlock, fontSizeFor } =
    new Function(src + "\nreturn { splitChars, layoutBlock, fontSizeFor };")();

let failed = 0;
function check(name, got, want) {
    const ok = JSON.stringify(got) === JSON.stringify(want);
    if (!ok) {
        failed++;
        console.log("FAIL", name, "\n  got ", JSON.stringify(got), "\n  want", JSON.stringify(want));
    } else {
        console.log("ok  ", name);
    }
}

// One horizontal subtitle line: 3 chars of 40 px at x = 100, y = 500
const h = layoutBlock({ vertical: false, lines: [
    { text: "今日は", rects: [[100, 500, 40, 50], [140, 500, 40, 50], [180, 500, 40, 50]] },
] });
check("horizontal box", [h.left, h.top, h.width, h.height], [100, 500, 120, 50]);
check("horizontal chars", h.lines[0].chars.map(c => [c.ch, c.marginInline, c.inlineSize]),
      [["今", 0, 40], ["日", 0, 40], ["は", 0, 40]]);
check("horizontal line", [h.lines[0].marginBlock, h.lines[0].blockSize], [0, 50]);

// Two centred lines of different widths, 10 px gap between them
const two = layoutBlock({ vertical: false, lines: [
    { text: "あい", rects: [[120, 400, 40, 50], [160, 400, 40, 50]] },
    { text: "うえお", rects: [[100, 460, 40, 50], [140, 460, 40, 50], [180, 460, 40, 50]] },
] });
check("two lines block", [two.left, two.top, two.width, two.height], [100, 400, 120, 110]);
check("first line indented", two.lines[0].chars[0].marginInline, 20);
check("second line gap", [two.lines[1].marginBlock, two.lines[1].blockSize], [10, 50]);

// Vertical manga: two columns, right one first in reading order
const v = layoutBlock({ vertical: true, lines: [
    { text: "ab", rects: [[200, 100, 30, 30], [200, 130, 30, 30]] },
    { text: "cd", rects: [[160, 110, 30, 30], [160, 140, 30, 30]] },
] });
check("vertical box", [v.left, v.top, v.width, v.height], [160, 100, 70, 70]);
check("right column first", v.lines[0].chars.map(c => c.ch).join(""), "ab");
check("column gap", [v.lines[1].marginBlock, v.lines[1].blockSize], [10, 30]);
check("second column starts lower", v.lines[1].chars[0].marginInline, 10);

// Surrogate pair kept together
const s = splitChars("a😀b", [[0, 0, 10, 10], [10, 0, 10, 10], [20, 0, 10, 10], [30, 0, 10, 10]]);
check("surrogates", s.map(c => [c.ch, c.rect]), [["a", [0, 0, 10, 10]], ["😀", [10, 0, 20, 10]], ["b", [30, 0, 10, 10]]]);

check("empty block", layoutBlock({ lines: [{ text: "", rects: [] }] }), null);
check("font full width", fontSizeFor(40, 50, 1, false), 40);
check("font half width", fontSizeFor(20, 50, 0.5, false), 40);
check("font capped", fontSizeFor(40, 20, 0.5, false), 26);
check("font vertical", fontSizeFor(30, 30, 1, true), 30);

if (failed > 0) {
    console.log(failed + " failed");
    Deno.exit(1);
}
console.log("all passed");
