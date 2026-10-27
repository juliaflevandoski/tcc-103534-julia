import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { crosswordPreviewUrl: String, quizGenerateUrl: String, fillBlanksGenerateUrl: String, orderingGenerateUrl: String, crosswordGenerateUrl: String, memoryGameGenerateUrl: String, memoryGameImageUrls: Object }

  static targets = [
    "typeSelect", "objectInput", "quizFields", "quizAiModal", "quizAiTopic", "quizAiDifficulty",
    "quizAiQuestionCount", "quizAiQuestionType", "quizAiTypeError", "quizAiGenerateButton",
    "quizAiStatus", "quizAiPreview", "quizAiPreviewQuestions", "quizAiApplyButton",
    "rawFields", "rawObject", "questionsList",
    "questionTemplate", "error", "fillBlanksFields", "fillTextTemplate", "blanksList",
    "blankTemplate", "blankError", "fillBlanksAiModal", "fillBlanksAiTopic", "fillBlanksAiDifficulty",
    "fillBlanksAiCount", "fillBlanksAiGenerateButton", "fillBlanksAiStatus", "fillBlanksAiPreview",
    "fillBlanksAiText", "fillBlanksAiAnswers", "fillBlanksAiApplyButton", "orderingFields",
    "orderingAiModal", "orderingAiTopic", "orderingAiDifficulty", "orderingAiItemType", "orderingAiItemCount",
    "orderingAiGenerateButton", "orderingAiStatus", "orderingAiPreview", "orderingAiInstructions",
    "orderingAiItems", "orderingAiApplyButton", "orderingInstructions", "orderingItemType",
    "orderingItemsList", "orderingItemTemplate", "orderingError", "crosswordFields", "crosswordAiModal",
    "crosswordAiTopic", "crosswordAiDifficulty", "crosswordAiWordCount", "crosswordAiGenerateButton",
    "crosswordAiStatus", "crosswordAiPreview", "crosswordAiWords", "crosswordAiApplyButton",
    "title", "crosswordInstructions", "crosswordWordsList", "crosswordWordTemplate", "crosswordSeed",
    "crosswordError", "crosswordPreview", "memoryGameFields", "memoryInstructions", "memoryPairType",
    "memoryGameAiModal", "memoryAiTopic", "memoryAiDifficulty", "memoryAiPairType", "memoryAiPairCount",
    "memoryAiGenerateButton", "memoryAiStatus", "memoryAiPreview", "memoryAiPairs", "memoryAiApplyButton", "memoryAiImageNotice",
    "memoryAiImageNotice", "memoryPairsList", "memoryPairTemplate", "memoryGameError", "memoryPreview", "memoryPreviewButton",
    "memoryEditButton", "memoryEditor", "submitButton"
  ]

  connect() {
    this.object = this.parseObject(this.objectInputTarget.value)
    this.questionSequence = 0
    this.generatedQuiz = null
    this.quizAiRequestPending = false
    this.generatedFillBlanks = null
    this.fillBlanksAiRequestPending = false
    this.generatedOrdering = null
    this.orderingAiRequestPending = false
    this.generatedCrossword = null
    this.crosswordAiRequestPending = false
    this.generatedMemoryGame = null
    this.memoryGameAiRequestPending = false
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

  openQuizAiModal(event) {
    event.preventDefault()
    if (!this.quizAiModalTarget.open) this.quizAiModalTarget.showModal()
  }

  keepQuizAiModalOpen(event) {
    event.preventDefault()
  }

  keepAiModalOpen(event) {
    event.preventDefault()
  }

  showQuizAiValidation(message, target) {
    this.quizAiStatusTarget.dataset.state = "error"
    this.quizAiStatusTarget.textContent = message
    target.setAttribute("aria-invalid", "true")
    target.focus()
  }

  async generateQuiz(event) {
    event.preventDefault()
    if (this.quizAiRequestPending) return

    const topic = this.quizAiTopicTarget.value.trim()
    const difficulty = this.quizAiDifficultyTarget.value
    const questionCount = this.quizAiQuestionCountTarget
    const questionTypes = this.quizAiQuestionTypeTargets.filter((input) => input.checked).map((input) => input.value)
    this.quizAiTypeErrorTarget.hidden = true

    if (!topic) {
      return this.showQuizAiValidation("Informe o tema do quiz.", this.quizAiTopicTarget)
    }
    if (!difficulty) {
      return this.showQuizAiValidation("Selecione a dificuldade do quiz.", this.quizAiDifficultyTarget)
    }
    const count = Number(questionCount.value)
    if (!questionCount.value || !Number.isInteger(count) || count < 1 || count > 20) {
      return this.showQuizAiValidation("Informe uma quantidade entre 1 e 20 questões.", questionCount)
    }
    if (!questionTypes.length) {
      this.quizAiTypeErrorTarget.textContent = "Selecione pelo menos um tipo de questão."
      this.quizAiTypeErrorTarget.hidden = false
      this.quizAiQuestionTypeTargets[0]?.focus()
      return
    }
    ;[ this.quizAiTopicTarget, this.quizAiDifficultyTarget, questionCount ].forEach((target) => target.removeAttribute("aria-invalid"))

    this.quizAiRequestPending = true
    this.generatedQuiz = null
    this.quizAiApplyButtonTarget.hidden = true
    this.quizAiPreviewTarget.hidden = true
    this.quizAiPreviewQuestionsTarget.replaceChildren()
    this.quizAiGenerateButtonTarget.disabled = true
    this.quizAiGenerateButtonTarget.textContent = "Gerando..."
    this.quizAiStatusTarget.dataset.state = "loading"
    this.quizAiStatusTarget.textContent = "A geração pode levar alguns instantes."

    try {
      const response = await fetch(this.quizGenerateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({
          topic,
          difficulty,
          question_count: count,
          question_types: questionTypes
        })
      })
      const payload = await response.json().catch(() => null)
      if (!response.ok) throw new Error(payload?.errors?.[0]?.message || "Não foi possível gerar o quiz. Tente novamente.")

      const quiz = payload?.data?.quiz
      if (!quiz || !Array.isArray(quiz.questions) || !quiz.questions.length) {
        throw new Error("A resposta recebida não contém um quiz válido.")
      }

      this.generatedQuiz = quiz
      this.renderQuizPreview(quiz)
      this.quizAiApplyButtonTarget.hidden = false
      this.quizAiStatusTarget.dataset.state = "success"
      this.quizAiStatusTarget.textContent = "Sugestão gerada. Revise as questões antes de aplicá-las ao editor."
    } catch (error) {
      this.quizAiStatusTarget.dataset.state = "error"
      this.quizAiStatusTarget.textContent = error.message || "Não foi possível gerar o quiz. Tente novamente."
    } finally {
      this.quizAiRequestPending = false
      this.quizAiGenerateButtonTarget.disabled = false
      this.quizAiGenerateButtonTarget.textContent = "Gerar sugestão"
    }
  }

  renderQuizPreview(quiz) {
    this.quizAiPreviewQuestionsTarget.replaceChildren()
    quiz.questions.forEach((question, index) => {
      const item = document.createElement("li")
      const statement = document.createElement("p")
      statement.textContent = question.statement
      item.append(statement)

      if (question.question_type === "multiple_choice") {
        const options = document.createElement("ul")
        const correctIds = new Set(question.correct_option_ids || [])
        question.options.forEach((option) => {
          const optionItem = document.createElement("li")
          optionItem.textContent = `${option.text}${correctIds.has(option.id) ? " (correta)" : ""}`
          options.append(optionItem)
        })
        item.append(options)
      }

      const answer = document.createElement("p")
      if (question.question_type === "true_false") {
        answer.textContent = `Gabarito: ${question.correct_option_ids[0] === "true" ? "Verdadeiro" : "Falso"}`
      } else if (question.question_type === "short_answer") {
        answer.textContent = `Resposta esperada: ${question.correct_answer}`
      }
      if (answer.textContent) item.append(answer)
      item.dataset.questionNumber = String(index + 1)
      this.quizAiPreviewQuestionsTarget.append(item)
    })
    this.quizAiPreviewTarget.hidden = false
  }

  applyGeneratedQuiz(event) {
    event.preventDefault()
    if (!this.generatedQuiz || this.typeSelectTarget.value !== "quiz") return
    if (this.quizHasExistingContent() && !window.confirm("Substituir as questões que já estão no editor pelo quiz gerado?")) return

    this.questionsListTarget.replaceChildren()
    this.generatedQuiz.questions.forEach((question) => this.addQuestion(null, question))
    this.updateQuestionTitles()
    this.errorTarget.hidden = true
    this.quizAiApplyButtonTarget.hidden = true
    this.quizAiStatusTarget.textContent = "Questões aplicadas ao editor. Revise e salve pelo fluxo normal."
    this.quizAiModalTarget.close()
  }

  quizHasExistingContent() {
    return [...this.questionsListTarget.querySelectorAll("[data-question]")].some((question) => {
      const statement = question.querySelector("[data-question-statement]").value.trim()
      const shortAnswer = question.querySelector("[data-question-short-answer-correct]").value.trim()
      const options = [...question.querySelectorAll("[data-option-text]")].some((input) => input.value.trim())
      const correct = [...question.querySelectorAll("[data-option-correct], [data-question-true-false-correct]")].some((input) => input.checked)
      return statement || shortAnswer || options || correct
    })
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
      const imageHint = sideElement.querySelector("[data-memory-image-hint]")
      wordInput.value = elements[side].content || ""
      imageHint.textContent = elements[side].ai_description || ""
      imageHint.hidden = !elements[side].ai_description
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
    this.memoryAiImageNoticeTarget.hidden = !expectedTypes.includes("image")

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
          sideElement.querySelector("[data-memory-image-hint]").textContent = ""
          sideElement.querySelector("[data-memory-image-hint]").hidden = true
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

  openFillBlanksAiModal(event) {
    event.preventDefault()
    if (!this.fillBlanksAiModalTarget.open) this.fillBlanksAiModalTarget.showModal()
  }

  async generateFillBlanks(event) {
    event.preventDefault()
    if (this.fillBlanksAiRequestPending) return

    const topic = this.fillBlanksAiTopicTarget.value.trim()
    const difficulty = this.fillBlanksAiDifficultyTarget.value
    const countField = this.fillBlanksAiCountTarget
    const count = Number(countField.value)
    if (!topic) return this.showAiValidation("Informe o tema do exercício.", this.fillBlanksAiTopicTarget, this.fillBlanksAiStatusTarget)
    if (!difficulty) return this.showAiValidation("Selecione a dificuldade.", this.fillBlanksAiDifficultyTarget, this.fillBlanksAiStatusTarget)
    if (!countField.value || !Number.isInteger(count) || count < 1 || count > 20) {
      return this.showAiValidation("Informe uma quantidade entre 1 e 20 lacunas.", countField, this.fillBlanksAiStatusTarget)
    }

    this.fillBlanksAiRequestPending = true
    this.generatedFillBlanks = null
    this.fillBlanksAiApplyButtonTarget.hidden = true
    this.fillBlanksAiPreviewTarget.hidden = true
    this.fillBlanksAiGenerateButtonTarget.disabled = true
    this.fillBlanksAiGenerateButtonTarget.textContent = "Gerando..."
    this.fillBlanksAiStatusTarget.dataset.state = "loading"
    this.fillBlanksAiStatusTarget.textContent = "A geração pode levar alguns instantes."

    try {
      const response = await fetch(this.fillBlanksGenerateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({ topic, difficulty, blank_count: count })
      })
      const payload = await response.json().catch(() => null)
      if (!response.ok) throw new Error(payload?.errors?.[0]?.message || "Não foi possível gerar as lacunas. Tente novamente.")

      const draft = payload?.data?.draft
      if (!draft || typeof draft.text_template !== "string" || !draft.blanks || typeof draft.blanks !== "object") {
        throw new Error("A resposta recebida não contém um exercício de lacunas válido.")
      }

      this.generatedFillBlanks = draft
      this.renderFillBlanksPreview(draft)
      this.fillBlanksAiApplyButtonTarget.hidden = false
      this.fillBlanksAiStatusTarget.dataset.state = "success"
      this.fillBlanksAiStatusTarget.textContent = "Sugestão gerada. Revise as lacunas e respostas antes de aplicá-las."
    } catch (error) {
      this.fillBlanksAiStatusTarget.dataset.state = "error"
      this.fillBlanksAiStatusTarget.textContent = error.message || "Não foi possível gerar as lacunas. Tente novamente."
    } finally {
      this.fillBlanksAiRequestPending = false
      this.fillBlanksAiGenerateButtonTarget.disabled = false
      this.fillBlanksAiGenerateButtonTarget.textContent = "Gerar sugestão"
    }
  }

  renderFillBlanksPreview(draft) {
    this.fillBlanksAiTextTarget.textContent = draft.text_template
    this.fillBlanksAiAnswersTarget.replaceChildren()
    Object.entries(draft.blanks).forEach(([id, answer]) => {
      const item = document.createElement("li")
      item.textContent = `Lacuna ${id}: ${answer}`
      this.fillBlanksAiAnswersTarget.append(item)
    })
    this.fillBlanksAiPreviewTarget.hidden = false
  }

  applyGeneratedFillBlanks(event) {
    event.preventDefault()
    if (!this.generatedFillBlanks || this.typeSelectTarget.value !== "fill_blanks") return
    const hasExistingContent = this.fillTextTemplateTarget.value.trim() ||
      [...this.blanksListTarget.querySelectorAll("[data-blank-answer]")].some((input) => input.value.trim())
    if (hasExistingContent && !window.confirm("Substituir o texto e as respostas atuais pelas lacunas geradas?")) return

    this.fillTextTemplateTarget.value = this.generatedFillBlanks.text_template
    this.blanksListTarget.replaceChildren()
    this.savedBlanks = { ...this.generatedFillBlanks.blanks }
    this.refreshBlanks()
    this.blankErrorTarget.hidden = true
    this.fillBlanksAiModalTarget.close()
  }

  openOrderingAiModal(event) {
    event.preventDefault()
    if (!this.orderingAiModalTarget.open) this.orderingAiModalTarget.showModal()
  }

  async generateOrdering(event) {
    event.preventDefault()
    if (this.orderingAiRequestPending) return

    const topic = this.orderingAiTopicTarget.value.trim()
    const difficulty = this.orderingAiDifficultyTarget.value
    const itemType = this.orderingAiItemTypeTarget.value
    const countField = this.orderingAiItemCountTarget
    const itemCount = Number(countField.value)
    if (!topic) return this.showAiValidation("Informe o tema do exercício.", this.orderingAiTopicTarget, this.orderingAiStatusTarget)
    if (!difficulty) return this.showAiValidation("Selecione a dificuldade.", this.orderingAiDifficultyTarget, this.orderingAiStatusTarget)
    if (!countField.value || !Number.isInteger(itemCount) || itemCount < 2 || itemCount > 20) {
      return this.showAiValidation("Informe uma quantidade entre 2 e 20 itens.", countField, this.orderingAiStatusTarget)
    }

    this.orderingAiRequestPending = true
    this.generatedOrdering = null
    this.orderingAiApplyButtonTarget.hidden = true
    this.orderingAiPreviewTarget.hidden = true
    this.orderingAiGenerateButtonTarget.disabled = true
    this.orderingAiGenerateButtonTarget.textContent = "Gerando..."
    this.orderingAiStatusTarget.dataset.state = "loading"
    this.orderingAiStatusTarget.textContent = "A geração pode levar alguns instantes."

    try {
      const response = await fetch(this.orderingGenerateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({ topic, difficulty, item_count: itemCount, item_type: itemType })
      })
      const payload = await response.json().catch(() => null)
      if (!response.ok) throw new Error(payload?.errors?.[0]?.message || "Não foi possível gerar a ordenação. Tente novamente.")

      const draft = payload?.data?.draft
      if (!draft || !Array.isArray(draft.items) || !Array.isArray(draft.correct_order)) {
        throw new Error("A resposta recebida não contém uma Ordenação válida.")
      }

      this.generatedOrdering = draft
      this.renderOrderingPreview(draft)
      this.orderingAiApplyButtonTarget.hidden = false
      this.orderingAiStatusTarget.dataset.state = "success"
      this.orderingAiStatusTarget.textContent = "Sugestão gerada na sequência correta. Revise antes de aplicá-la."
    } catch (error) {
      this.orderingAiStatusTarget.dataset.state = "error"
      this.orderingAiStatusTarget.textContent = error.message || "Não foi possível gerar a ordenação. Tente novamente."
    } finally {
      this.orderingAiRequestPending = false
      this.orderingAiGenerateButtonTarget.disabled = false
      this.orderingAiGenerateButtonTarget.textContent = "Gerar sugestão"
    }
  }

  renderOrderingPreview(draft) {
    this.orderingAiInstructionsTarget.textContent = draft.instructions
    this.orderingAiItemsTarget.replaceChildren()
    const itemsById = new Map(draft.items.map((item) => [ item.id, item ]))
    draft.correct_order.forEach((id) => {
      const item = itemsById.get(id)
      if (!item) return

      const row = document.createElement("li")
      row.textContent = item.label
      this.orderingAiItemsTarget.append(row)
    })
    this.orderingAiPreviewTarget.hidden = false
  }

  applyGeneratedOrdering(event) {
    event.preventDefault()
    if (!this.generatedOrdering || this.typeSelectTarget.value !== "ordering") return
    const hasExistingContent = this.orderingInstructionsTarget.value.trim() ||
      [...this.orderingItemsListTarget.querySelectorAll("[data-ordering-item-value]")].some((input) => input.value.trim())
    if (hasExistingContent && !window.confirm("Substituir as instruções e os itens atuais pela Ordenação gerada?")) return

    this.orderingInstructionsTarget.value = this.generatedOrdering.instructions
    this.orderingItemTypeTarget.value = this.generatedOrdering.item_type
    this.orderingItemsListTarget.replaceChildren()
    this.generatedOrdering.items.forEach((item) => this.appendOrderingItem(item))
    this.updateOrderingItemNumbers()
    this.changeOrderingItemType()
    this.orderingErrorTarget.hidden = true
    this.orderingAiModalTarget.close()
  }

  openCrosswordAiModal(event) {
    event.preventDefault()
    if (!this.crosswordAiModalTarget.open) this.crosswordAiModalTarget.showModal()
  }

  async generateCrossword(event) {
    event.preventDefault()
    if (this.crosswordAiRequestPending) return

    const topic = this.crosswordAiTopicTarget.value.trim()
    const difficulty = this.crosswordAiDifficultyTarget.value
    const countField = this.crosswordAiWordCountTarget
    const wordCount = Number(countField.value)
    if (!topic) return this.showAiValidation("Informe o tema da cruzadinha.", this.crosswordAiTopicTarget, this.crosswordAiStatusTarget)
    if (!difficulty) return this.showAiValidation("Selecione a dificuldade.", this.crosswordAiDifficultyTarget, this.crosswordAiStatusTarget)
    if (!countField.value || !Number.isInteger(wordCount) || wordCount < 2 || wordCount > 20) {
      return this.showAiValidation("Informe uma quantidade entre 2 e 20 palavras.", countField, this.crosswordAiStatusTarget)
    }

    this.crosswordAiRequestPending = true
    this.generatedCrossword = null
    this.crosswordAiApplyButtonTarget.hidden = true
    this.crosswordAiPreviewTarget.hidden = true
    this.crosswordAiGenerateButtonTarget.disabled = true
    this.crosswordAiGenerateButtonTarget.textContent = "Gerando..."
    this.crosswordAiStatusTarget.dataset.state = "loading"
    this.crosswordAiStatusTarget.textContent = "A geração e a montagem da grade podem levar alguns instantes."

    try {
      const response = await fetch(this.crosswordGenerateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({ topic, difficulty, word_count: wordCount })
      })
      const payload = await response.json().catch(() => null)
      if (!response.ok) throw new Error(payload?.errors?.[0]?.message || "Não foi possível gerar a cruzadinha. Tente novamente.")

      const draft = payload?.data?.draft
      if (!draft || !Array.isArray(draft.words) || !draft.grid || !Number.isInteger(draft.layout_seed)) {
        throw new Error("A resposta recebida não contém uma cruzadinha válida.")
      }

      this.generatedCrossword = draft
      this.renderCrosswordAiPreview(draft)
      this.crosswordAiApplyButtonTarget.hidden = false
      this.crosswordAiStatusTarget.dataset.state = "success"
      this.crosswordAiStatusTarget.textContent = "Palavras e pistas geradas. Revise antes de aplicá-las ao editor."
    } catch (error) {
      this.crosswordAiStatusTarget.dataset.state = "error"
      this.crosswordAiStatusTarget.textContent = error.message || "Não foi possível gerar a cruzadinha. Tente novamente."
    } finally {
      this.crosswordAiRequestPending = false
      this.crosswordAiGenerateButtonTarget.disabled = false
      this.crosswordAiGenerateButtonTarget.textContent = "Gerar sugestão"
    }
  }

  renderCrosswordAiPreview(draft) {
    this.crosswordAiWordsTarget.replaceChildren()
    draft.words.forEach((word) => {
      const item = document.createElement("li")
      item.textContent = `${word.word} - ${word.clue}`
      this.crosswordAiWordsTarget.append(item)
    })
    this.crosswordAiPreviewTarget.hidden = false
  }

  applyGeneratedCrossword(event) {
    event.preventDefault()
    if (!this.generatedCrossword || this.typeSelectTarget.value !== "crossword") return
    const hasExistingContent = this.crosswordInstructionsTarget.value.trim() ||
      [...this.crosswordWordsListTarget.querySelectorAll("[data-crossword-word]")].some((row) =>
        row.querySelector("[data-crossword-word-value]").value.trim() || row.querySelector("[data-crossword-clue-value]").value.trim()
      )
    if (hasExistingContent && !window.confirm("Substituir as palavras e pistas atuais pela cruzadinha gerada?")) return

    this.crosswordInstructionsTarget.value = this.generatedCrossword.instructions
    this.crosswordWordsListTarget.replaceChildren()
    this.generatedCrossword.words.forEach((word) => this.addCrosswordWord(null, word))
    this.crosswordSeedTarget.value = this.generatedCrossword.layout_seed
    this.crosswordPreviewValid = true
    this.displayCrosswordPreview(this.generatedCrossword)
    this.updateCrosswordSubmitState()
    this.crosswordAiModalTarget.close()
  }

  openMemoryGameAiModal(event) {
    event.preventDefault()
    if (!this.memoryGameAiModalTarget.open) this.memoryGameAiModalTarget.showModal()
  }

  async generateMemoryGame(event) {
    event.preventDefault()
    if (this.memoryGameAiRequestPending) return

    const topic = this.memoryAiTopicTarget.value.trim()
    const difficulty = this.memoryAiDifficultyTarget.value
    const pairType = this.memoryAiPairTypeTarget.value
    const countField = this.memoryAiPairCountTarget
    const pairCount = Number(countField.value)
    if (!topic) return this.showAiValidation("Informe o tema do jogo.", this.memoryAiTopicTarget, this.memoryAiStatusTarget)
    if (!difficulty) return this.showAiValidation("Selecione a dificuldade.", this.memoryAiDifficultyTarget, this.memoryAiStatusTarget)
    if (!countField.value || !Number.isInteger(pairCount) || pairCount < 2 || pairCount > 20) {
      return this.showAiValidation("Informe uma quantidade entre 2 e 20 pares.", countField, this.memoryAiStatusTarget)
    }

    this.memoryGameAiRequestPending = true
    this.generatedMemoryGame = null
    this.memoryAiApplyButtonTarget.hidden = true
    this.memoryAiPreviewTarget.hidden = true
    this.memoryAiGenerateButtonTarget.disabled = true
    this.memoryAiGenerateButtonTarget.textContent = "Gerando..."
    this.memoryAiStatusTarget.dataset.state = "loading"
    this.memoryAiStatusTarget.textContent = "A geração pode levar alguns instantes."

    try {
      const response = await fetch(this.memoryGameGenerateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({ topic, difficulty, pair_count: pairCount, pair_type: pairType })
      })
      const payload = await response.json().catch(() => null)
      if (!response.ok) throw new Error(payload?.errors?.[0]?.message || "Não foi possível gerar os pares. Tente novamente.")

      const draft = payload?.data?.draft
      if (!draft || !Array.isArray(draft.pairs) || draft.pairs.length !== pairCount) {
        throw new Error("A resposta recebida não contém pares válidos.")
      }

      this.generatedMemoryGame = draft
      this.renderMemoryGamePreview(draft)
      this.memoryAiApplyButtonTarget.hidden = false
      this.memoryAiStatusTarget.dataset.state = "success"
      this.memoryAiStatusTarget.textContent = "Pares gerados. Revise as relações antes de aplicá-las ao editor."
    } catch (error) {
      this.memoryAiStatusTarget.dataset.state = "error"
      this.memoryAiStatusTarget.textContent = error.message || "Não foi possível gerar os pares. Tente novamente."
    } finally {
      this.memoryGameAiRequestPending = false
      this.memoryAiGenerateButtonTarget.disabled = false
      this.memoryAiGenerateButtonTarget.textContent = "Gerar sugestão"
    }
  }

  renderMemoryGamePreview(draft) {
    this.memoryAiPairsTarget.replaceChildren()
    draft.pairs.forEach((pair) => {
      const item = document.createElement("li")
      item.textContent = [ "left", "right" ].map((side) => {
        const element = pair[side]
        return element.type === "word" ? element.content : `[Imagem a adicionar: ${element.ai_description}]`
      }).join(" ↔ ")
      this.memoryAiPairsTarget.append(item)
    })
    this.memoryAiPreviewTarget.hidden = false
  }

  applyGeneratedMemoryGame(event) {
    event.preventDefault()
    if (!this.generatedMemoryGame || this.typeSelectTarget.value !== "memory_game") return
    const hasExistingContent = this.memoryInstructionsTarget.value.trim() ||
      [...this.memoryPairsListTarget.querySelectorAll("[data-memory-pair]")].some((row) => {
        const words = [...row.querySelectorAll("[data-memory-word]")].some((input) => input.value.trim())
        const images = [...row.querySelectorAll("[data-memory-image]")].some((input) => input.files.length || input.dataset.existingBlobId)
        return words || images
      })
    if (hasExistingContent && !window.confirm("Substituir as instruções e os pares atuais pelos pares gerados?")) return

    this.memoryInstructionsTarget.value = this.generatedMemoryGame.instructions
    this.memoryPairTypeTarget.value = this.generatedMemoryGame.pair_type
    this.memoryPairsListTarget.replaceChildren()
    this.generatedMemoryGame.pairs.forEach((pair) => this.addMemoryPair(null, pair))
    this.changeMemoryPairType()
    const requiresImages = this.generatedMemoryGame.pair_type !== "word_word"
    this.memoryAiImageNoticeTarget.hidden = !requiresImages
    this.memoryGameErrorTarget.hidden = true
    this.memoryGameAiModalTarget.close()
  }

  showAiValidation(message, target, statusTarget) {
    statusTarget.dataset.state = "error"
    statusTarget.textContent = message
    target.setAttribute("aria-invalid", "true")
    target.focus()
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
      const crossword = this.crosswordInput()
      this.objectInputTarget.value = JSON.stringify({
        instructions: crossword.instructions,
        layout_seed: Number(crossword.seed),
        words: crossword.words
      })
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