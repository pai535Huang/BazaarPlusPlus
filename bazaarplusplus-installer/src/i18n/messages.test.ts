import { describe, expect, it } from "vitest";
import { formatMessage, messages } from "./messages";

describe("messages catalog", () => {
  it("defines the same keys for every locale", () => {
    const zhKeys = Object.keys(messages.zh).sort();
    const enKeys = Object.keys(messages.en).sort();
    expect(enKeys).toEqual(zhKeys);
  });

  it("returns a different string per locale for the same key", () => {
    expect(formatMessage("zh", "navInstall")).toBe("安装");
    expect(formatMessage("en", "navInstall")).toBe("Install");
  });
});

describe("formatMessage", () => {
  it("returns the raw message when no params are given", () => {
    expect(formatMessage("en", "confirmInstall")).toBe("Confirm Install");
  });

  it("interpolates named placeholders", () => {
    expect(formatMessage("en", "resetDataPartialFailure", { count: 3 })).toBe(
      "3 local data item(s) could not be deleted. Close the game and stream sources, then try again.",
    );
    expect(formatMessage("zh", "streamWindowOffset", { count: 3 })).toBe(
      "向前补 3 条记录",
    );
  });
});
