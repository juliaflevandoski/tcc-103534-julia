# Prepara e renderiza gráficos temporais (SVG via Stimulus). Não calcula notas nem médias:
# só valida e repassa os valores já preparados, por exemplo, pelo OfficialAttemptSeries.
#
# Contrato do payload (enviado ao Stimulus como JSON):
#   type:        "line" ou "bar"
#   unit:        "percent" (valores de 0 a 100) ou "count" (inteiros >= 0)
#   title:       título acessível
#   description: descrição acessível
#   weeks:       [{ label: "05/01", full: "Semana de 05/01/2026" }]
#   series:      [{ label: "Média semanal", values: [66.7, nil, 80.0] }]
#                values tem um item por semana; nil significa "sem dados" e nunca é desenhado como zero.
module TimeSeriesChartHelper
  CHART_TYPES = %w[line bar].freeze
  CHART_UNITS = %w[percent count].freeze

  # weeks: objetos com #week_start (Date). series: [{ label:, metric: :average }], em que metric é
  # um método de cada semana, ou [{ label:, values: [...] }] com os valores já prontos.
  def time_series_chart_payload(type:, unit:, title:, description:, weeks:, series:)
    weeks = Array(weeks)
    payload = {
      type: type.to_s,
      unit: unit.to_s,
      title: title.to_s,
      description: description.to_s,
      weeks: weeks.map { |week| { label: week.week_start.strftime("%d/%m"), full: "Semana de #{week.week_start.strftime('%d/%m/%Y')}" } },
      series: Array(series).map do |entry|
        values = entry[:values] || weeks.map { |week| week.public_send(entry.fetch(:metric)) }
        { label: entry.fetch(:label).to_s, values: values.map { |value| value.nil? ? nil : value } }
      end
    }
    validate_time_series_payload!(payload)
    payload
  end

  def time_series_chart(empty_message: "Ainda não há tentativas oficiais para exibir.", id: nil, **options)
    render "shared/time_series_chart",
           chart: time_series_chart_payload(**options),
           chart_id: id || "time-series-chart-#{SecureRandom.hex(4)}",
           empty_message:
  end

  def time_series_cell(value, unit)
    return "Sem dados" if value.nil?

    unit == "percent" ? number_to_percentage(value, precision: 1) : value.to_s
  end

  private

  def validate_time_series_payload!(payload)
    raise ArgumentError, "Tipo de gráfico inválido" unless CHART_TYPES.include?(payload[:type])
    raise ArgumentError, "Unidade inválida" unless CHART_UNITS.include?(payload[:unit])
    raise ArgumentError, "Informe ao menos uma série" if payload[:series].empty?

    payload[:series].each do |series|
      raise ArgumentError, "Série com quantidade de valores diferente da de semanas" unless series[:values].length == payload[:weeks].length

      series[:values].each do |value|
        next if value.nil?

        valid = payload[:unit] == "percent" ? value.is_a?(Numeric) && value.between?(0, 100) : value.is_a?(Integer) && value >= 0
        raise ArgumentError, "Valor fora do intervalo da unidade: #{value.inspect}" unless valid
      end
    end
  end
end
