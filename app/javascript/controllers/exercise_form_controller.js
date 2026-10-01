import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { crosswordPreviewUrl: String, memoryGameImageUrls: Object }

  static targets = [
    "typeSelect", "objectInput", "quizFields", "rawFields", "rawObject", "questionsList",
    "questionTemplate", "error", "fillBlanksFields", "fillTextTemplate", "blanksList",
    "blankTemplate", "blankError", "orderingFields", "orderingInstructions", "orderingItemType",
    "orderingItemsList", "orderingItemTemplate", "orderingError", "crosswordFields",
    "title", "crosswordInstructions", "crosswordWordsList", "crosswordWordTemplate", "crosswordSeed",
    "crosswordError", "crosswordPreview", "memoryGameFields", "memoryInstructions", "memoryPairType",
    "memoryPairsList", "memoryPairTemplate", "memoryGameError", "memoryPreview", "memoryPreviewButton",
    "memoryEditButton", "memoryEditor", "submitButton"
  ]

  connect() {
    this.object = this.parseObject(this.objectInputTarget.value)
    this.questionSequence = 0
    this.rawObjectTarget.value = JSON.stringify(this.object, null, 2)
    this.questionsForEditing().forEach((question) => this.addQuestion(null, question))
    if (!this.questionsListTarget.children.length) this.addQuestion()
    this.fillTextTemplateTarget.value = this.object.text_template || ""
    this.savedBlanks = this.object.blanks || {}
    this.refreshBlanks()
    this.orderingInstructionsTarget.value = this.object.instructions || ""
    this.orderingItemTypeTarget.value = this.object.item_type || this.inferOrderingItemType()
    this.orderingItemsForEditing().forEach((item) => this.appendOrderingItem(item))
    if (!this.orderingItemsListTarget.children.length) {
      this.appendOrderingItem()
      this.appendOrderingItem()
    }
    this.changeOrderingItemType()
    this.crosswordPreviewValid = false
    this.crosswordInstructionsTarget.value = this.object.instructions || ""
    const crosswordWords = Array.isArray(this.object.words) ? this.object.words : []
    crosswordWords.forEach((word) => this.addCrosswordWord(null, word))
    if (!crosswordWords.length) {
      this.addCrosswordWord()
      this.addCrosswordWord()
    }
    if (this.object.grid && crosswordWords.length) {
      this.crosswordSeedTarget.value = this.object.layout_seed || 0
      this.crosswordPreviewValid = true
      this.displayCrosswordPreview(this.object)
    }
    this.memoryInstructionsTarget.value = this.object.instructions || ""
    this.memoryPairTypeTarget.value = this.object.pair_type || "word_word"
    const memoryPairs = Array.isArray(this.object.pairs) ? this.object.pairs : []
    memoryPairs.forEach((pair) => this.addMemoryPair(null, pair))
    if (!memoryPairs.length) {
      this.addMemoryPair()
      this.addMemoryPair()
    }
    this.changeMemoryPairType()
    this.changeType()
  }

  changeType() {
    const isQuiz = this.typeSelectTarget.value === "quiz"
    const isFillBlanks = this.typeSelectTarget.value === "fill_blanks"
    const isOrdering = this.typeSelectTarget.value === "ordering"
    const isCrossword = this.typeSelectTarget.value === "crossword"
    const isMemoryGame = this.typeSelectTarget.value === "memory_game"
    this.titleTarget.required = isCrossword || isMemoryGame
    this.quizFieldsTarget.hidden = !isQuiz
    this.fillBlanksFieldsTarget.hidden = !isFillBlanks
    this.orderingFieldsTarget.hidden = !isOrdering
    this.crosswordFieldsTarget.hidden = !isCrossword
    this.memoryGameFieldsTarget.hidden = !isMemoryGame
    this.memoryGameFieldsTarget.disabled = !isMemoryGame
    this.rawFieldsTarget.hidden = isQuiz || isFillBlanks || isOrdering || isCrossword || isMemoryGame
    this.rawObjectTarget.disabled = isQuiz || isFillBlanks || isOrdering || isCrossword || isMemoryGame
    this.errorTarget.hidden = true
    this.blankErrorTarget.hidden = true
    this.orderingErrorTarget.hidden = true
    this.updateCrosswordSubmitState()
  }

  addMemoryPair(event, pair = {}) {
    event?.preventDefault()
    const fragment = this.memoryPairTemplateTarget.content.cloneNode(true)
    const row = fragment.querySelector("[data-memory-pair]")
    row.dataset.pairUiId = crypto.randomUUID()
    const elements = { left: pair.left || {}, right: pair.right || {} }

    for (const side of ["left", "right"]) {
      const sideElement = row.querySelector(`[data-memory-side='${side}']`)
      const wordInput = sideElement.querySelector("[data-memory-word]")
      const imageInput = sideElement.querySelector("[data-memory-image]")
      const imagePreview = sideElement.querySelector("[data-memory-image-preview]")
      const currentImage = sideElement.querySelector("[data-memory-image-current]")
      wordInput.value = elements[side].content || ""
      imageInput.dataset.uploadKey = `${row.dataset.pairUiId}-${side}`
      imageInput.dataset.existingBlobId = elements[side].blob_id || ""
      imageInput.addEventListener("change", () => this.changeMemoryImage(imageInput, imagePreview, currentImage))
      const imageUrl = this.memoryGameImageUrlsValue?.[imageInput.dataset.existingBlobId]
      if (imageUrl) {
        imagePreview.src = imageUrl
        imagePreview.hidden = false
        currentImage.hidden = false
      }
    }

    this.memoryPairsListTarget.append(fragment)
    this.updateMemoryPairNumbers()
    this.changeMemoryPairType()
  }

  removeMemoryPair(event) {
    event.preventDefault()
    event.currentTarget.closest("[data-memory-pair]").remove()
    this.updateMemoryPairNumbers()
  }

  updateMemoryPairNumbers() {
    this.memoryPairsListTarget.querySelectorAll("[data-memory-pair-number]").forEach((number, index) => {
      number.textContent = index + 1
    })
  }

  changeMemoryPairType() {
    const pairTypes = {
      word_word: [ "word", "word" ],
      word_image: [ "word", "image" ],
      image_image: [ "image", "image" ]
    }
    const expectedTypes = pairTypes[this.memoryPairTypeTarget.value] || pairTypes.word_word

    this.memoryPairsListTarget.querySelectorAll("[data-memory-pair]").forEach((row) => {
      ["left", "right"].forEach((side, sideIndex) => {
        const expectedType = expectedTypes[sideIndex]
        const previousType = row.dataset[`${side}Type`]
        const sideElement = row.querySelector(`[data-memory-side='${side}']`)
        const wordInput = sideElement.querySelector("[data-memory-word]")
        const imageInput = sideElement.querySelector("[data-memory-image]")
        if (previousType && previousType !== expectedType) {
          wordInput.value = ""
          imageInput.value = ""
          imageInput.name = ""
          imageInput.dataset.existingBlobId = ""
          sideElement.querySelector("[data-memory-image-preview]").hidden = true
          sideElement.querySelector("[data-memory-image-current]").hidden = true
        }
        row.dataset[`${side}Type`] = expectedType
        sideElement.querySelector("[data-memory-word-field]").hidden = expectedType !== "word"
        sideElement.querySelector("[data-memory-image-field]").hidden = expectedType !== "image"
      })
    })
  }

  changeMemoryImage(input, preview, currentImage) {
    const file = input.files[0]
    if (!file) return

    input.dataset.existingBlobId = ""
    input.name = `exercise[memory_images][${input.dataset.uploadKey}]`
    preview.src = URL.createObjectURL(file)
    preview.hidden = false
    currentImage.hidden = true
  }

  serializeMemoryGame() {
    const instructions = this.memoryInstructionsTarget.value.trim()
    const pairType = this.memoryPairTypeTarget.value
    const pairs = [...this.memoryPairsListTarget.querySelectorAll("[data-memory-pair]")]
    if (!instructions) return this.rejectMemoryGameSubmission("Informe as instruções do jogo.")
    if (pairs.length < 2) return this.rejectMemoryGameSubmission("Adicione pelo menos dois pares.")

    const elementTypes = {
      word_word: [ "word", "word" ],
      word_image: [ "word", "image" ],
      image_image: [ "image", "image" ]
    }[pairType]
    const serializedPairs = []
    for (const row of pairs) {
      const serialized = {}
      for (const [sideIndex, side] of ["left", "right"].entries()) {
        const sideElement = row.querySelector(`[data-memory-side='${side}']`)
        if (elementTypes[sideIndex] === "word") {
          const content = sideElement.querySelector("[data-memory-word]").value.trim()
          if (!content) return this.rejectMemoryGameSubmission("Preencha todos os campos dos pares.")
          serialized[side] = { type: "word", content }
        } else {
          const imageInput = sideElement.querySelector("[data-memory-image]")
          if (imageInput.files[0]) {
            serialized[side] = { type: "image", upload_key: imageInput.dataset.uploadKey }
          } else if (imageInput.dataset.existingBlobId) {
            serialized[side] = { type: "image", blob_id: Number(imageInput.dataset.existingBlobId) }
          } else {
            return this.rejectMemoryGameSubmission("Selecione uma imagem para cada elemento visual.")
          }
        }
      }
      serializedPairs.push(serialized)
    }

    this.memoryGameErrorTarget.hidden = true
    return { instructions, pair_type: pairType, pairs: serializedPairs }
  }

  rejectMemoryGameSubmission(message) {
    this.memoryGameErrorTarget.textContent = message
    this.memoryGameErrorTarget.hidden = false
    return null
  }

  previewMemoryGame(event) {
    event.preventDefault()
    const object = this.serializeMemoryGame()
    if (!object) return

    const pairNames = { word_word: "Palavra ↔ Palavra", word_image: "Palavra ↔ Imagem", image_image: "Imagem ↔ Imagem" }
    const cards = object.pairs.flatMap((pair, pairIndex) => ["left", "right"].map((side) => ({
      element: pair[side],
      row: this.memoryPairsListTarget.querySelectorAll("[data-memory-pair]")[pairIndex]
        .querySelector(`[data-memory-side='${side}']`)
    })))
    for (let index = cards.length - 1; index > 0; index -= 1) {
      const swapIndex = Math.floor(Math.random() * (index + 1))
      ;[cards[index], cards[swapIndex]] = [cards[swapIndex], cards[index]]
    }

    this.memoryPreviewTarget.replaceChildren()
    const heading = document.createElement("h3")
    heading.textContent = "Prévia do jogo"
    const summary = document.createElement("p")
    summary.textContent = `${pairNames[object.pair_type]} · ${cards.length} cartas`
    const board = document.createElement("div")
    board.className = "memory-board memory-board-preview"
    cards.forEach(({ element, row }) => board.append(this.createMemoryCardFace(element, row)))
    this.memoryPreviewTarget.append(heading, summary, board)
    this.memoryPreviewTarget.hidden = false
    this.memoryEditorTarget.hidden = true
    this.memoryPreviewButtonTarget.hidden = true
    this.memoryEditButtonTarget.hidden = false
  }

  createMemoryCardFace(element, row) {
    const card = document.createElement("div")
    card.className = "memory-card is-revealed"
    if (element.type === "word") {
      card.textContent = element.content
    } else {
      const imageInput = row.querySelector("[data-memory-image]")
      const imageUrl = imageInput.files[0]
        ? URL.createObjectURL(imageInput.files[0])
        : this.memoryGameImageUrlsValue?.[element.blob_id]
      if (imageUrl) {
        const image = document.createElement("img")
        image.src = imageUrl
        image.alt = "Imagem da carta"
        card.append(image)
      }
    }
    return card
  }

  editMemoryGame(event) {
    event.preventDefault()
    this.memoryPreviewTarget.hidden = true
    this.memoryEditorTarget.hidden = false
    this.memoryPreviewButtonTarget.hidden = false
    this.memoryEditButtonTarget.hidden = true
  }

  addQuestion(event, question = {}) {
    event?.preventDefault()
    this.questionSequence += 1
    const questionId = `question-${this.questionSequence}`
    const fragment = this.questionTemplateTarget.content.cloneNode(true)
    const questionElement = fragment.querySelector("[data-question]")
    questionElement.dataset.questionId = questionId
    questionElement.dataset.nextOptionId = "1"
    questionElement._optionIds = new Set()
    questionElement.querySelector("[data-question-title]").textContent = `Pergunta ${this.questionSequence}`
    questionElement.querySelector("[data-question-type]").value = this.normalizeQuestionType(question.question_type)
    questionElement.querySelector("[data-question-statement]").value = question.statement || ""

    const trueFalseInputs = questionElement.querySelectorAll("[data-question-true-false-correct]")
    trueFalseInputs.forEach((input) => {
      input.name = `correct-true-false-${questionId}`
      input.checked = (question.correct_option_ids || []).includes(input.value)
    })
    questionElement.querySelector("[data-question-short-answer-correct]").value = question.correct_answer || ""

    this.questionsListTarget.append(fragment)
    const savedOptions = Array.isArray(question.options) ? question.options : []
    if (savedOptions.length) {
      savedOptions.forEach((option) => this.appendOption(questionElement, option, (question.correct_option_ids || []).includes(option.id)))
    } else {
      this.appendOption(questionElement)
      this.appendOption(questionElement)
    }
    this.updateQuestionType(questionElement)
  }

  removeQuestion(event) {
    event.preventDefault()
    event.target.closest("[data-question]").remove()
    this.updateQuestionTitles()
  }

  updateQuestionTitles() {
    this.questionsListTarget.querySelectorAll("[data-question-title]").forEach((title, index) => {
      title.textContent = `Pergunta ${index + 1}`
    })
  }

  changeQuestionType(event) {
    this.updateQuestionType(event.currentTarget.closest("[data-question]"))
  }

  updateQuestionType(questionElement) {
    const questionType = questionElement.querySelector("[data-question-type]").value
    const optionsPanel = questionElement.querySelector("[data-question-options-panel]")
    const trueFalsePanel = questionElement.querySelector("[data-question-true-false-panel]")
    const shortAnswerPanel = questionElement.querySelector("[data-question-short-answer-panel]")
    optionsPanel.hidden = questionType !== "multiple_choice"
    optionsPanel.disabled = questionType !== "multiple_choice"
    trueFalsePanel.hidden = questionType !== "true_false"
    trueFalsePanel.disabled = questionType !== "true_false"
    shortAnswerPanel.hidden = questionType !== "short_answer"
    shortAnswerPanel.disabled = questionType !== "short_answer"
  }

  addOption(event) {
    event?.preventDefault()
    const questionElement = event.currentTarget.closest("[data-question]")
    this.appendOption(questionElement)
  }

  appendOption(questionElement, option = {}, correct = false) {
    const template = questionElement.querySelector("[data-question-option-template]")
    const fragment = template.content.cloneNode(true)
    const row = fragment.querySelector("[data-option-row]")
    const questionId = questionElement.dataset.questionId
    let id = option.id || `option-${questionElement.dataset.nextOptionId++}`
    while (questionElement._optionIds.has(id)) id = `option-${questionElement.dataset.nextOptionId++}`
    questionElement._optionIds.add(id)
    row.dataset.optionId = id
    row.querySelector("[data-option-text]").value = option.text || ""
    const correctInput = row.querySelector("[data-option-correct]")
    correctInput.name = `correct-option-${questionId}`
    correctInput.value = id
    correctInput.checked = correct
    questionElement.querySelector("[data-question-options-list]").append(fragment)
  }

  removeOption(event) {
    event.preventDefault()
    event.target.closest("[data-option-row]").remove()
  }

  convertSelection(event) {
    event.preventDefault()
    const editor = this.fillTextTemplateTarget
    const start = editor.selectionStart
    const end = editor.selectionEnd
    if (start === end) return this.rejectBlankSubmission("Selecione um trecho do texto para transformá-lo em lacuna.")

    const markers = [...editor.value.matchAll(/\{\{(\d+)\}\}/g)].map((match) => Number(match[1]))
    const markerId = Math.max(0, ...markers) + 1
    editor.setRangeText(`{{${markerId}}}`, start, end, "end")
    this.refreshBlanks()
    editor.focus()
    this.blankErrorTarget.hidden = true
  }

  refreshBlanks() {
    const previousAnswers = { ...this.savedBlanks }
    this.blanksListTarget.querySelectorAll("[data-blank-row]").forEach((row) => {
      previousAnswers[row.dataset.blankId] = row.querySelector("[data-blank-answer]").value
    })

    const markerIds = [...new Set([...this.fillTextTemplateTarget.value.matchAll(/\{\{(\d+)\}\}/g)].map((match) => match[1]))]
    this.blanksListTarget.replaceChildren()
    markerIds.forEach((markerId, index) => {
      const fragment = this.blankTemplateTarget.content.cloneNode(true)
      const row = fragment.querySelector("[data-blank-row]")
      row.dataset.blankId = markerId
      row.querySelector("[data-blank-number]").textContent = index + 1
      row.querySelector("[data-blank-answer]").value = previousAnswers[markerId] || ""
      this.blanksListTarget.append(fragment)
    })
    this.savedBlanks = Object.fromEntries(markerIds.map((markerId) => [markerId, previousAnswers[markerId] || ""]))
  }

  changeOrderingItemType() {
    const isNumeric = this.orderingItemTypeTarget.value === "numbers"
    this.orderingItemsListTarget.querySelectorAll("[data-ordering-item-value]").forEach((input) => {
      input.inputMode = isNumeric ? "numeric" : "text"
      if (isNumeric) {
        input.pattern = "-?\\d+"
      } else {
        input.removeAttribute("pattern")
      }
      input.placeholder = isNumeric ? "Ex.: -3" : "Digite uma palavra ou elemento"
    })
  }

  addOrderingItem(event) {
    event?.preventDefault()
    this.appendOrderingItem()
    this.updateOrderingItemNumbers()
    this.changeOrderingItemType()
  }

  appendOrderingItem(item = {}) {
    const fragment = this.orderingItemTemplateTarget.content.cloneNode(true)
    const row = fragment.querySelector("[data-ordering-item]")
    row.dataset.itemId = item.id || `item-${this.nextOrderingItemId()}`
    row.querySelector("[data-ordering-item-value]").value = item.label || ""
    this.orderingItemsListTarget.append(fragment)
    this.updateOrderingItemNumbers()
  }

  nextOrderingItemId() {
    const ids = [...this.orderingItemsListTarget.querySelectorAll("[data-item-id]")]
      .map((item) => Number(item.dataset.itemId.replace("item-", "")))
      .filter(Number.isInteger)
    return Math.max(0, ...ids) + 1
  }

  removeOrderingItem(event) {
    event.preventDefault()
    event.target.closest("[data-ordering-item]").remove()
    this.updateOrderingItemNumbers()
  }

  updateOrderingItemNumbers() {
    this.orderingItemsListTarget.querySelectorAll("[data-ordering-item-number]").forEach((number, index) => {
      number.textContent = index + 1
    })
  }

  startOrderingItemDrag(event) {
    this.draggedOrderingItem = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", event.currentTarget.dataset.itemId)
  }

  allowOrderingItemDrop(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dropOrderingItem(event) {
    event.preventDefault()
    const target = event.currentTarget
    if (!this.draggedOrderingItem || target === this.draggedOrderingItem) return

    const rows = [...this.orderingItemsListTarget.querySelectorAll("[data-ordering-item]")]
    const draggedIndex = rows.indexOf(this.draggedOrderingItem)
    const targetIndex = rows.indexOf(target)
    this.orderingItemsListTarget.insertBefore(this.draggedOrderingItem, draggedIndex < targetIndex ? target.nextSibling : target)
    this.updateOrderingItemNumbers()
  }

  endOrderingItemDrag() {
    this.draggedOrderingItem = null
  }

  addCrosswordWord(event, word = {}) {
    event?.preventDefault()
    const fragment = this.crosswordWordTemplateTarget.content.cloneNode(true)
    const row = fragment.querySelector("[data-crossword-word]")
    const wordInput = row.querySelector("[data-crossword-word-value]")
    const clueInput = row.querySelector("[data-crossword-clue-value]")
    wordInput.value = word.word || ""
    clueInput.value = word.clue || word.hint || ""
    wordInput.addEventListener("input", () => this.invalidateCrosswordPreview())
    clueInput.addEventListener("input", () => this.invalidateCrosswordPreview())
    this.crosswordWordsListTarget.append(fragment)
  }

  removeCrosswordWord(event) {
    event.preventDefault()
    event.target.closest("[data-crossword-word]").remove()
    this.invalidateCrosswordPreview()
  }

  invalidateCrosswordPreview() {
    this.crosswordPreviewValid = false
    this.crosswordPreviewTarget.hidden = true
    this.crosswordErrorTarget.hidden = true
    this.updateCrosswordSubmitState()
  }

  updateCrosswordSubmitState() {
    if (this.typeSelectTarget.value === "crossword") this.submitButtonTarget.disabled = !this.crosswordPreviewValid
    else this.submitButtonTarget.disabled = false
  }

  crosswordInput() {
    return {
      instructions: this.crosswordInstructionsTarget.value.trim(),
      seed: this.crosswordSeedTarget.value || "0",
      words: [...this.crosswordWordsListTarget.querySelectorAll("[data-crossword-word]")].map((row) => ({
        word: row.querySelector("[data-crossword-word-value]").value.trim(),
        clue: row.querySelector("[data-crossword-clue-value]").value.trim()
      }))
    }
  }

  async previewCrossword(event) {
    event.preventDefault()
    const seed = crypto.getRandomValues(new Uint32Array(1))[0]
    this.crosswordSeedTarget.value = seed
    await this.requestCrosswordPreview()
  }

  async regenerateCrossword(event) {
    event.preventDefault()
    const previousSeed = Number(this.crosswordSeedTarget.value || 0)
    this.crosswordSeedTarget.value = (previousSeed + 1 + Math.floor(Math.random() * 100_000)) >>> 0
    await this.requestCrosswordPreview()
  }

  async requestCrosswordPreview() {
    this.crosswordErrorTarget.hidden = true
    this.crosswordPreviewValid = false
    this.updateCrosswordSubmitState()

    try {
      const response = await fetch(this.crosswordPreviewUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify(this.crosswordInput())
      })
      const payload = await response.json()
      if (!response.ok) {
        const details = [...(payload.errors || []).map((error) => error.message), ...(payload.unplaced_words || []).map((word) => `Não posicionada: ${word}`)]
        this.crosswordErrorTarget.textContent = details.join(" ") || "Não foi possível gerar a cruzadinha."
        this.crosswordErrorTarget.hidden = false
        return
      }

      this.displayCrosswordPreview(payload.data.object)
      this.crosswordPreviewValid = true
      this.updateCrosswordSubmitState()
    } catch {
      this.crosswordErrorTarget.textContent = "Falha ao comunicar com o servidor para gerar a prévia."
      this.crosswordErrorTarget.hidden = false
    }
  }

  displayCrosswordPreview(object) {
    this.crosswordPreviewTarget.replaceChildren()
    this.crosswordPreviewTarget.hidden = false

    const heading = document.createElement("h3")
    heading.textContent = "Prévia da cruzadinha"
    this.crosswordPreviewTarget.append(heading)

    const board = document.createElement("div")
    board.className = "crossword-board-scroll"
    const grid = document.createElement("table")
    grid.className = "crossword-grid crossword-teacher-grid"
    object.grid.cells.forEach((row) => {
      const tableRow = document.createElement("tr")
      row.forEach((letter) => {
        const cell = document.createElement("td")
        if (letter) cell.textContent = letter
        else cell.className = "crossword-blocked-cell"
        tableRow.append(cell)
      })
      grid.append(tableRow)
    })
    board.append(grid)
    this.crosswordPreviewTarget.append(board)

    for (const [direction, label] of [["across", "Horizontal"], ["down", "Vertical"]]) {
      const entries = object.words.filter((word) => word.direction === direction).sort((left, right) => left.number - right.number)
      if (!entries.length) continue
      const clueHeading = document.createElement("h4")
      clueHeading.textContent = label
      const list = document.createElement("ol")
      entries.forEach((entry) => {
        const item = document.createElement("li")
        item.value = entry.number
        item.textContent = `${entry.word} - ${entry.clue}`
        list.append(item)
      })
      this.crosswordPreviewTarget.append(clueHeading, list)
    }
  }

  prepareObject(event) {
    if (this.typeSelectTarget.value === "fill_blanks") {
      const fillBlanksObject = this.serializeFillBlanks()
      if (!fillBlanksObject) return this.rejectBlankSubmission(this.blankErrorTarget.textContent)
      this.objectInputTarget.value = JSON.stringify(fillBlanksObject)
      return
    }

    if (this.typeSelectTarget.value === "ordering") {
      const orderingObject = this.serializeOrdering()
      if (!orderingObject) return this.rejectOrderingSubmission(event, this.orderingErrorTarget.textContent)
      this.objectInputTarget.value = JSON.stringify(orderingObject)
      return
    }

    if (this.typeSelectTarget.value === "crossword") {
      if (!this.crosswordPreviewValid) {
        event.preventDefault()
        this.crosswordErrorTarget.textContent = "Gere uma prévia válida antes de salvar a cruzadinha."
        this.crosswordErrorTarget.hidden = false
        return
      }
      this.objectInputTarget.value = JSON.stringify(this.crosswordInput())
      return
    }

    if (this.typeSelectTarget.value === "memory_game") {
      const memoryGameObject = this.serializeMemoryGame()
      if (!memoryGameObject) {
        event.preventDefault()
        return
      }
      this.objectInputTarget.value = JSON.stringify(memoryGameObject)
      return
    }

    if (this.typeSelectTarget.value !== "quiz") {
      this.objectInputTarget.value = this.rawObjectTarget.value
      return
    }

    const questions = [...this.questionsListTarget.querySelectorAll("[data-question]")]
    if (!questions.length) return this.rejectSubmission(event, "Adicione pelo menos uma pergunta ao Quiz.")

    const serializedQuestions = []
    for (const questionElement of questions) {
      const questionType = questionElement.querySelector("[data-question-type]").value
      const statement = questionElement.querySelector("[data-question-statement]").value.trim()
      if (!statement) return this.rejectSubmission(event, "Preencha o enunciado de cada pergunta.")

      const question = { question_type: questionType, statement }
      if (questionType === "multiple_choice") {
        const options = [...questionElement.querySelectorAll("[data-option-row]")]
          .map((row) => ({ id: row.dataset.optionId, text: row.querySelector("[data-option-text]").value.trim(), correct: row.querySelector("[data-option-correct]").checked }))
          .filter((option) => option.text)
        const correctOptionIds = options.filter((option) => option.correct).map((option) => option.id)
        if (options.length < 2) return this.rejectSubmission(event, "Adicione pelo menos duas alternativas em cada pergunta de múltipla escolha.")
        if (correctOptionIds.length !== 1) return this.rejectSubmission(event, "Marque uma resposta correta em cada pergunta de múltipla escolha.")
        question.options = options.map(({ id, text }) => ({ id, text }))
        question.correct_option_ids = correctOptionIds
      } else if (questionType === "true_false") {
        const correctInput = [...questionElement.querySelectorAll("[data-question-true-false-correct]")].find((input) => input.checked)
        if (!correctInput) return this.rejectSubmission(event, "Selecione a resposta correta em cada pergunta de verdadeiro ou falso.")
        question.correct_option_ids = [correctInput.value]
      } else {
        const correctAnswer = questionElement.querySelector("[data-question-short-answer-correct]").value.trim()
        if (!correctAnswer) return this.rejectSubmission(event, "Informe a resposta esperada em cada pergunta de resposta curta.")
        question.correct_answer = correctAnswer
      }
      serializedQuestions.push(question)
    }

    this.objectInputTarget.value = JSON.stringify({ questions: serializedQuestions })
  }

  serializeOrdering() {
    const instructions = this.orderingInstructionsTarget.value.trim()
    const items = [...this.orderingItemsListTarget.querySelectorAll("[data-ordering-item]")]
      .map((row) => ({ id: row.dataset.itemId, label: row.querySelector("[data-ordering-item-value]").value.trim() }))
    if (!instructions) {
      this.orderingErrorTarget.textContent = "Informe a pergunta ou instrução da ordenação."
      return null
    }
    if (items.length < 2) {
      this.orderingErrorTarget.textContent = "Adicione pelo menos dois itens para ordenar."
      return null
    }
    if (items.some((item) => !item.label)) {
      this.orderingErrorTarget.textContent = "Preencha todos os itens da ordenação."
      return null
    }
    if (this.orderingItemTypeTarget.value === "numbers" && items.some((item) => !/^-?\d+$/.test(item.label))) {
      this.orderingErrorTarget.textContent = "Use apenas números inteiros, incluindo negativos se necessário."
      return null
    }

    const correctOrder = items.map((item) => item.id)
    return { instructions, item_type: this.orderingItemTypeTarget.value, items, correct_order: correctOrder }
  }

  rejectOrderingSubmission(event, message) {
    event.preventDefault()
    this.orderingErrorTarget.textContent = message
    this.orderingErrorTarget.hidden = false
  }

  serializeFillBlanks() {
    const template = this.fillTextTemplateTarget.value.trim()
    const rows = [...this.blanksListTarget.querySelectorAll("[data-blank-row]")]
    const markerIds = [...new Set([...template.matchAll(/\{\{(\d+)\}\}/g)].map((match) => match[1]))]
    if (!template) {
      this.blankErrorTarget.textContent = "Informe o texto do exercício."
      return null
    }
    if (!markerIds.length) {
      this.blankErrorTarget.textContent = "Selecione ao menos um trecho para transformá-lo em lacuna."
      return null
    }

    const answers = Object.fromEntries(rows.map((row) => [row.dataset.blankId, row.querySelector("[data-blank-answer]").value.trim()]))
    if (markerIds.some((markerId) => !answers[markerId])) {
      this.blankErrorTarget.textContent = "Informe uma resposta para cada lacuna."
      return null
    }

    const normalizedIds = Object.fromEntries(markerIds.map((markerId, index) => [markerId, String(index + 1)]))
    const textTemplate = template.replace(/\{\{(\d+)\}\}/g, (_marker, markerId) => `{{${normalizedIds[markerId]}}}`)
    const blanks = Object.fromEntries(markerIds.map((markerId) => [normalizedIds[markerId], answers[markerId]]))
    return { text_template: textTemplate, blanks }
  }

  rejectBlankSubmission(message) {
    this.blankErrorTarget.textContent = message
    this.blankErrorTarget.hidden = false
  }

  rejectSubmission(event, message) {
    event.preventDefault()
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  parseObject(value) {
    try {
      const parsed = JSON.parse(value || "{}")
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
    } catch {
      return {}
    }
  }

  questionsForEditing() {
    if (Array.isArray(this.object.questions)) return this.object.questions
    if (!this.object.question_type) return []
    return [{ ...this.object, question_type: this.normalizeQuestionType(this.object.question_type) }]
  }

  normalizeQuestionType(questionType) {
    if (questionType === "multiple_answer") return "multiple_choice"
    return ["multiple_choice", "true_false", "short_answer"].includes(questionType) ? questionType : "multiple_choice"
  }

  orderingItemsForEditing() {
    if (!Array.isArray(this.object.items)) return []
    const itemsById = new Map(this.object.items.map((item) => [item.id, item]))
    const orderedIds = Array.isArray(this.object.correct_order) ? this.object.correct_order : this.object.items.map((item) => item.id)
    return [...orderedIds.map((id) => itemsById.get(id)).filter(Boolean), ...this.object.items.filter((item) => !orderedIds.includes(item.id))]
  }

  inferOrderingItemType() {
    const labels = Array.isArray(this.object.items) ? this.object.items.map((item) => item.label) : []
    return labels.length && labels.every((label) => /^-?\d+$/.test(String(label))) ? "numbers" : "words"
  }
}