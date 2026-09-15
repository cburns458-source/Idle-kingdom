import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { prepareDatabase } from "../data/loadDatabase";
import { GROUP_MINING, InventorySorter } from "../inventory/sort";
import { CodexIndex, includeInCodexCatalog } from "./codex";

const rawDatabase = JSON.parse(
  readFileSync(
    resolve(process.cwd(), "content/data/game-database.json"),
    "utf8",
  ),
);

describe("codex index", () => {
  const { launch } = prepareDatabase(rawDatabase);
  const sorter = new InventorySorter(launch);
  const codex = new CodexIndex(launch);

  it("lists every launch item and enemy except pets, cosmetics, and quest items", () => {
    const catalogIds = new Set(
      launch.Items.filter((row) => includeInCodexCatalog(row)).map(
        (row) => row["Item ID"],
      ),
    );
    expect(new Set(codex.items.map((row) => row.itemId))).toEqual(catalogIds);
    expect(catalogIds.has("ITEM-0299")).toBe(false);
    expect(catalogIds.has("ITEM-0296")).toBe(false);
    expect(catalogIds.has("ITEM-0320")).toBe(false);
    expect(codex.item("ITEM-0299")?.displayName).toBe("Stolen Coin Purse");
    expect(codex.item("ITEM-0296")?.displayName).toBe("Traveler's Tunic");
    expect(codex.item("ITEM-0320")?.displayName).toBe("Fly Pet");
    expect(new Set(codex.enemies.map((row) => row.enemyId))).toEqual(
      new Set(launch.Enemies.map((row) => row["Enemy ID"])),
    );
    expect(codex.item("ITEM-0209")?.displayName).toBe("Ancient Alloy");
    expect(codex.item("ITEM-0276")?.displayName).toBe("Ancient Alloy Sword");
    expect(codex.item("ITEM-0325")).toBeUndefined();
    expect(codex.item("ITEM-0346")).toBeUndefined();
    expect(codex.item("ITEM-0091")).toBeUndefined();
    expect(codex.item("ITEM-0096")).toBeUndefined();
    expect(codex.item("ITEM-0144")).toBeUndefined();
    expect(codex.item("ITEM-0286")).toBeUndefined();
    expect(
      launch.Items.find((row) => row["Item ID"] === "ITEM-0263")?.[
        "Base Sell Value"
      ],
    ).toBe(550);
    expect(
      launch.Items.find((row) => row["Item ID"] === "ITEM-0250")?.[
        "Base Sell Value"
      ],
    ).toBe(850);
    expect(
      launch.Items.find((row) => row["Item ID"] === "ITEM-0009")?.[
        "Base Sell Value"
      ],
    ).toBe(280);
    expect(
      launch.Items.find((row) => row["Item ID"] === "ITEM-0010")?.[
        "Base Sell Value"
      ],
    ).toBe(180);
  });

  it("lists gathering actions with gem tables kept separate from the merged drop pool", () => {
    expect(codex.actions.some((row) => row.actionId === "ACN-0018")).toBe(true);
    expect(codex.actions.every((row) => row.category === "Gathering")).toBe(
      true,
    );
    expect(codex.action("ACN-0001")).toBeUndefined();
    expect(codex.action("ACN-0036")).toBeUndefined();
    expect(codex.action("ACN-0166")).toBeUndefined();
    expect(codex.action("ACN-0167")).toBeUndefined();
    expect(codex.action("ACN-0168")).toBeUndefined();
    const mine = codex.action("ACN-0018")!;
    expect(mine.displayName.toLowerCase()).toContain("copper");
    expect(mine.tables.map((table) => table.label)).toEqual(["Drops", "Gems"]);
    const ore = mine.tables.find((table) => table.label === "Drops")!;
    expect(ore.drops.map((row) => row.displayName)).toContain("Copper Ore");
    expect(ore.drops.map((row) => row.displayName)).not.toContain("Sapphire");
    const gems = mine.tables.find((table) => table.label === "Gems")!;
    expect(gems.dropChance).toBe(1);
    expect(gems.drops.map((row) => row.displayName)).toContain("Sapphire");
    expect(
      codex.actionsMatching("mine copper").map((row) => row.actionId),
    ).toContain("ACN-0018");
  });

  it("folds hunting secondary and tertiary drops into the primary pool", () => {
    const hunt = codex.action("ACN-0014")!;
    expect(hunt.tables.map((table) => table.label)).toEqual(["Drops"]);
    const names = hunt.tables[0]!.drops.map((row) => row.displayName);
    expect(names).toEqual(
      expect.arrayContaining([
        "Venison",
        "Leather",
        "Elk Horns",
        "Animal Tendons",
      ]),
    );
  });

  it("uses the same inventory groups as the bag", () => {
    for (const item of launch.Items) {
      expect(codex.item(item["Item ID"])!.group).toBe(
        sorter.groupOf(item["Item ID"]),
      );
    }
    expect(
      codex
        .itemsMatching(GROUP_MINING)
        .every((row) => row.group === GROUP_MINING),
    ).toBe(true);
    expect(
      codex.itemsMatching(undefined, "copper").map((row) => row.itemId),
    ).toContain("ITEM-0003");
  });

  it("links copper ore to its mine action", () => {
    const ore = codex.item("ITEM-0003")!;
    expect(ore.obtainedFrom.some((row) => row.actionId === "ACN-0018")).toBe(
      true,
    );
    const mine = ore.obtainedFrom.find((row) => row.actionId === "ACN-0018")!;
    expect(mine.title.toLowerCase()).toContain("copper");
    expect(mine.locations.length).toBeGreaterThan(0);
  });

  it("shows recipes that make and use items", () => {
    const potato = codex.item("ITEM-0058")!;
    expect(potato.craftedBy[0]?.isProject).toBe(false);
    expect(potato.craftedBy[0]?.ingredients.map((row) => row.itemId)).toContain(
      "ITEM-0025",
    );
    expect(
      codex
        .item("ITEM-0025")!
        .usedIn.some((row) => row.output.itemId === "ITEM-0058"),
    ).toBe(true);
  });

  it("shows projects that make and use items", () => {
    const iron = codex.item("ITEM-0128")!;
    expect(iron.craftedBy[0]?.isProject).toBe(true);
    expect(iron.craftedBy[0]?.id).toBe("PRJ-0003");
    const steel = codex.item("ITEM-0130")!;
    expect(steel.craftedBy.every((row) => row.isProject)).toBe(true);
    expect(steel.craftedBy.map((row) => row.id)).toContain("PRJ-0005");
    expect(steel.craftedBy.every((row) => !row.id.startsWith("RCP-"))).toBe(
      true,
    );
    expect(
      codex
        .item("ITEM-0045")!
        .usedIn.some((row) => row.output.itemId === "ITEM-0308"),
    ).toBe(true);
    expect(
      codex.item("ITEM-0197")!.usedIn.some((row) => row.id === "PRJ-0049"),
    ).toBe(true);
  });

  it("lists cow drops on the bestiary and as item obtain sources", () => {
    expect(
      codex
        .item("ITEM-0054")!
        .obtainedFrom.some((row) => row.enemyId === "ENM-0001"),
    ).toBe(true);
    expect(
      codex
        .item("ITEM-0054")!
        .obtainedFrom.filter((row) => row.enemyId === "ENM-0001"),
    ).toHaveLength(1);
    expect(
      codex
        .item("ITEM-0054")!
        .obtainedFrom.some((row) => row.actionId === "ACN-0001"),
    ).toBe(false);
    const cow = codex.enemy("ENM-0001")!;
    expect(cow.drops.map((row) => row.itemId)).toEqual(
      expect.arrayContaining(["ITEM-0054", "ITEM-0045"]),
    );
    expect(cow.drops.filter((row) => row.itemId === "ITEM-0054")).toHaveLength(
      1,
    );
    expect(
      cow.drops.find((row) => row.itemId === "ITEM-0054")?.dropRatePercent,
    ).toEqual(expect.any(Number));
    expect(cow.locations.map((row) => row.displayName)).toContain("The Farm");
    expect(
      codex.enemy("ENM-0008")!.locations.map((row) => row.displayName),
    ).toEqual(expect.arrayContaining(["Wizard's Tower", "Castle Crypt"]));
    expect(codex.enemy("ENM-0008")!.drops.map((row) => row.itemId)).toEqual(
      expect.arrayContaining(["ITEM-0129", "ITEM-0012"]),
    );
    expect(
      codex.enemy("ENM-0008")!.drops.map((row) => row.itemId),
    ).not.toContain("ITEM-0286");
    expect(
      codex.enemy("ENM-0008")!.drops.find((row) => row.itemId === "ITEM-0129")
        ?.dropRatePercent,
    ).toBe(60);
    expect(
      codex.enemy("ENM-0009")!.drops.map((row) => row.itemId),
    ).not.toContain("ITEM-0286");
    expect(
      codex.enemy("ENM-0006")!.drops.map((row) => row.itemId),
    ).not.toContain("ITEM-0144");
  });

  it("lists secondary combat action loot as obtain sources that open the bestiary enemy", () => {
    const staff = codex.item("ITEM-0122")!;
    const fight = staff.obtainedFrom.find((row) => row.enemyId === "ENM-0004");
    expect(fight?.kind).toBe("enemy");
    expect(fight?.actionId).toBeUndefined();
    expect(fight?.title.toLowerCase()).toContain("goblin");
  });

  it("lists excavator pickaxe quest reward but not chef hat quest", () => {
    const pick = codex.item("ITEM-0313")!;
    expect(
      pick.obtainedFrom.some(
        (row) => row.kind === "quest" && row.questId === "QST-0008",
      ),
    ).toBe(true);
    const hat = codex.item("ITEM-0165")!;
    expect(hat.obtainedFrom.some((row) => row.kind === "quest")).toBe(false);
  });

  it("hides golden spud sources and mystery harvest action", () => {
    expect(codex.item("ITEM-0026")!.obtainedFrom).toEqual([]);
    expect(
      codex.items.some((row) =>
        row.obtainedFrom.some((source) => source.actionId === "ACN-0036"),
      ),
    ).toBe(false);
  });

  it("labels Mother Squid and Squidling XP as Fishing", () => {
    const mother = codex.enemy("ENM-0023");
    const squidling = codex.enemy("ENM-0024");
    if (mother) expect(mother.xpSkillLabel).toBe("Fishing");
    if (squidling) expect(squidling.xpSkillLabel).toBe("Fishing");
  });
});
