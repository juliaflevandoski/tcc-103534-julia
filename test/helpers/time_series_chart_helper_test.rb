require "test_helper"

class TimeSeriesChartHelperTest < ActionView::TestCase
  Week = Struct.new(:week_start, :average, :attempts_count, keyword_init: true)

  def weeks
    [
      Week.new(week_start: Date.new(2026, 1, 5), average: 80.0, attempts_count: 2),
      Week.new(week_start: Date.new(2026, 1, 12), average: nil, attempts_count: 0),
      Week.new(week_start: Date.new(2026, 1, 19), average: 0.0, attempts_count: 3)
    ]
  end

  def payload(**overrides)
    time_series_chart_payload(
      **{ type: "line", unit: "percent", title: "Média semanal", description: "Média das notas oficiais por semana.",
          weeks:, series: [ { label: "Média", metric: :average } ] }.merge(overrides)
    )
  end

  test "payload follows the documented contract and keeps missing grades as nil" do
    chart = payload

    assert_equal %w[line percent], chart.values_at(:type, :unit)
    assert_equal [ { label: "05/01", full: "Semana de 05/01/2026" }, { label: "12/01", full: "Semana de 12/01/2026" }, { label: "19/01", full: "Semana de 19/01/2026" } ], chart[:weeks]
    assert_equal [ { label: "Média", values: [ 80.0, nil, 0.0 ] } ], chart[:series]
  end

  test "values are passed through without recalculation and explicit values are accepted" do
    chart = payload(type: "bar", unit: "count", series: [ { label: "Exercícios", metric: :attempts_count }, { label: "Outra", values: [ 1, 2, 3 ] } ])

    assert_equal [ 2, 0, 3 ], chart[:series][0][:values]
    assert_equal [ 1, 2, 3 ], chart[:series][1][:values]
  end

  test "payload rejects invalid contracts" do
    assert_raises(ArgumentError) { payload(type: "pie") }
    assert_raises(ArgumentError) { payload(unit: "seconds") }
    assert_raises(ArgumentError) { payload(series: []) }
    assert_raises(ArgumentError) { payload(series: [ { label: "x", values: [ 1.0, 2.0 ] } ]) }
    assert_raises(ArgumentError) { payload(series: [ { label: "x", values: [ 101.0, nil, 0.0 ] } ]) }
    assert_raises(ArgumentError) { payload(series: [ { label: "x", values: [ -1.0, nil, 0.0 ] } ]) }
    assert_raises(ArgumentError) { payload(unit: "count", series: [ { label: "x", values: [ 1.5, 0, 0 ] } ]) }
    assert_raises(ArgumentError) { payload(unit: "count", series: [ { label: "x", values: [ -1, 0, 0 ] } ]) }
  end

  test "renders the stimulus container, accessible caption and a value table with a no-data marker" do
    html = time_series_chart(id: "demo", type: "line", unit: "percent", title: "Média semanal", description: "Notas oficiais.", weeks:, series: [ { label: "Média", metric: :average } ])
    doc = Nokogiri::HTML.fragment(html)

    figure = doc.at_css("figure#demo.time-series-chart[data-controller='time-series-chart']")
    assert figure
    json = JSON.parse(figure["data-time-series-chart-chart-value"])
    assert_equal [ 80.0, nil, 0.0 ], json["series"][0]["values"]
    assert_equal "Média semanal", doc.at_css(".time-series-chart-title").text
    assert_equal "Notas oficiais.", doc.at_css(".time-series-chart-description").text
    assert doc.at_css("[data-time-series-chart-target='canvas']")
    assert doc.at_css("details[data-time-series-chart-target='table'][open]")
    assert_equal [ "Semana", "Média" ], doc.css("thead th").map(&:text)
    assert_equal [ "80.0%", "Sem dados", "0.0%" ], doc.css("tbody td").map { |cell| cell.text.strip }
    assert_equal 1, doc.css("td.time-series-chart-no-data").length
    assert_equal [ "Semana de 05/01/2026", "Semana de 12/01/2026", "Semana de 19/01/2026" ], doc.css("tbody th[scope='row']").map(&:text)
  end

  test "count tables show integers and zero as a real value" do
    html = time_series_chart(id: "counts", type: "bar", unit: "count", title: "Exercícios", description: "Por semana.", weeks:, series: [ { label: "Realizados", metric: :attempts_count } ])

    assert_equal [ "2", "0", "3" ], Nokogiri::HTML.fragment(html).css("tbody td").map { |cell| cell.text.strip }
  end

  test "empty series renders a status message instead of a chart" do
    html = time_series_chart(id: "empty", type: "line", unit: "percent", title: "Vazio", description: "Sem dados.", weeks: [], series: [ { label: "Média", values: [] } ])
    doc = Nokogiri::HTML.fragment(html)

    assert_equal "Ainda não há tentativas oficiais para exibir.", doc.at_css(".time-series-chart-empty-message[role='status']").text
    assert_nil doc.at_css("table")
    assert_nil doc.at_css("[data-time-series-chart-target='canvas']")
  end

  test "single point renders one table row" do
    single = [ weeks.first ]
    html = time_series_chart(id: "single", type: "line", unit: "percent", title: "Um ponto", description: "Uma semana.", weeks: single, series: [ { label: "Média", metric: :average } ])

    assert_equal 1, Nokogiri::HTML.fragment(html).css("tbody tr").length
  end

  test "accepts OfficialAttemptSeries weeks directly" do
    week = OfficialAttemptSeries::Week.new(week_start: Date.new(2026, 1, 5), attempts_count: 1, cumulative_attempts_count: 1, distinct_students_count: 1, rated_count: 1, average: 50.0, cumulative_average: 50.0)
    chart = payload(weeks: [ week ], series: [ { label: "Média", metric: :average }, { label: "Acumulada", metric: :cumulative_average } ])

    assert_equal [ [ 50.0 ], [ 50.0 ] ], chart[:series].map { |series| series[:values] }
  end
end
