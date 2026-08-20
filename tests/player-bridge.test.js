const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const vm = require("node:vm")

const bridgeSource = fs.readFileSync(require.resolve("../extension/player-bridge.js"), "utf8")

function bridgeHarness(instance) {
  const attributes = new Map()
  const listeners = new Map()
  let current = instance
  const document = {
    documentElement: {
      getAttribute(name) { return attributes.get(name) || null },
      setAttribute(name, value) { attributes.set(name, value) }
    },
    addEventListener(name, listener) { listeners.set(name, listener) },
    dispatchEvent() {}
  }
  const context = {
    document,
    Event: class Event { constructor(type) { this.type = type } },
    MusicKit: { getInstance() { return current } },
    OmarchyAppleMusicPlayer: { serializePlayer() { return {} } },
    setInterval() { return 1 },
    clearInterval() {},
    setTimeout(callback) { callback() },
    window: { addEventListener() {} }
  }
  vm.runInNewContext(bridgeSource, context)

  return {
    send(command) {
      attributes.set("data-omarchy-apple-music-command", JSON.stringify(command))
      listeners.get("omarchy-apple-music-command")()
    },
    discover(next) {
      current = next
      listeners.get("musickitloaded")()
    }
  }
}

test("queue item clicks select the existing MusicKit queue index", () => {
  let selected = -1
  const instance = {
    addEventListener() {},
    changeToMediaAtIndex(index) {
      selected = index
      return Promise.resolve()
    },
    playAt() {
      assert.fail("playAt inserts items instead of selecting an existing queue item")
    }
  }

  bridgeHarness(instance).send({ name: "playAt", value: 4 })
  assert.equal(selected, 4)
})

test("queue item clicks ignore non-integer positions", () => {
  let selections = 0
  const instance = {
    addEventListener() {},
    changeToMediaAtIndex() {
      selections += 1
    }
  }

  const harness = bridgeHarness(instance)
  harness.send({ name: "playAt", value: "invalid" })
  harness.send({ name: "playAt", value: 1.5 })
  assert.equal(selections, 0)
})

test("binding a replacement MusicKit instance releases the previous listeners", () => {
  const bound = []
  const released = []
  const first = {
    addEventListener(name) { bound.push(name) },
    removeEventListener(name) { released.push(name) }
  }
  const second = {
    addEventListener() {},
    removeEventListener() {}
  }

  const harness = bridgeHarness(first)
  assert.ok(bound.length > 0)
  harness.discover(second)
  assert.deepEqual(released, bound)
})
