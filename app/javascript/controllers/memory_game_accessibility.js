export function memoryCardAccessibleName(card, found = false) {
  const isWord = card.type === "word"
  const description = (isWord ? card.content : card.description)?.trim()
  const prefix = found ? "Par encontrado" : (!isWord && description ? "Imagem revelada" : "Carta revelada")
  const content = description || (isWord ? "" : "imagem")

  return content ? `${prefix}: ${content}` : prefix
}

export function memoryCardImageAlt(description) {
  return typeof description === "string" ? description.trim() : ""
}
