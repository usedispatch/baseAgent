import aos from "./aos";
import fs from "fs";
import path from "node:path";
import assert from "node:assert";
import { describe, test, before } from "node:test";

describe("Tests", () => {
  let env: aos;

  before(async () => {
    const source = fs.readFileSync(
      path.join(__dirname, "../../process/.build/output.lua"),
      "utf-8"
    );
    env = new aos(source);
    await env.init();
  });

  test("load DbAdmin module", async () => {
    const dbAdminCode = fs.readFileSync(
      path.join(__dirname, "../../process/.build/dbAdmin.lua"),
      "utf-8"
    );
    const result = await env.send({
      Action: "Eval",
      Data: `
  local function _load() 
    ${dbAdminCode}
  end
  _G.package.loaded["DbAdmin"] = _load()
  return "ok"
      `,
    });
    console.log("result DbAdmin Module", result);
    assert.equal(result.Output.data, "ok");
  });

  test("load source", async () => {
    const code = fs.readFileSync(
      path.join(__dirname, "../../process/.build/output.lua"),
      "utf-8"
    );
    const result = await env.send({ Action: "Eval", Data: code });
    console.log("result load source", result);
    // assert.equal(result.Output.data, "OK");
  });
  test("deposit", async () => {
    const result = await env.send({
      Action: "deposit",
      Data: JSON.stringify({ amount: 100 }),
    });
    console.log("result deposit", result.Messages);
    // assert.equal(result.Output.data, 100);
  });
  test("withdraw", async () => {
    const result = await env.send({
      Action: "withdraw",
      Data: JSON.stringify({ amount: 10 }),
    });
    console.log("result withdraw", result.Messages);
    // assert.equal(result.Output.data, 0);
  });
  test("getDeposit", async () => {
    const result = await env.send({
      Action: "getDeposit",
    });
    console.log("result getDeposit", result.Messages);
    // assert.equal(result.Output.data, 0);
  });
  test("trade", async () => {
    const result = await env.send({
      Action: "trade",
      Data: JSON.stringify({ price: 100 }),
    });
    console.log("result trade", result.Messages);
    // assert.equal(result.Output.data, 0);
  });
});
