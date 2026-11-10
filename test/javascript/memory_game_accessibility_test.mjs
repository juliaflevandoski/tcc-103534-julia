import assert from "node:assert/strict"
import test from "node:test"
import { memoryCardAccessibleName, memoryCardImageAlt } from "../../app/javascript/controllers/memory_game_accessibility.js"

test("revealed word cards include the word in their accessible name", () => {
  assert.equal(memoryCardAccessibleName({ type: "word", content: "Cachorro" }), "Carta revelada: Cachorro")
})

test("revealed image cards use an available description without inventing one", () => {
  assert.equal(memoryCardAccessibleName({ type: "image", description: "Um cachorro marrom" }), "Imagem revelada: Um cachorro marrom")
  assert.equal(memoryCardAccessibleName({ type: "image" }), "Carta revelada: imagem")
  assert.equal(memoryCardImageAlt(" Um cachorro marrom "), "Um cachorro marrom")
  assert.equal(memoryCardImageAlt(undefined), "")
})

test("found cards retain their identifying content", () => {
  assert.equal(memoryCardAccessibleName({ type: "word", content: "Cachorro" }, true), "Par encontrado: Cachorro")
  assert.equal(memoryCardAccessibleName({ type: "image", description: "Um cachorro marrom" }, true), "Par encontrado: Um cachorro marrom")
})
