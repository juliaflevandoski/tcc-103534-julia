class StudentLevel
  XP_PER_LEVEL = 100

  Result = Struct.new(:level, :total_xp, :xp_in_level, :xp_for_next, :percent, keyword_init: true)

  def self.call(xp)
    total_xp = [ xp.to_i, 0 ].max
    xp_in_level = total_xp % XP_PER_LEVEL

    Result.new(
      level: total_xp / XP_PER_LEVEL + 1,
      total_xp:,
      xp_in_level:,
      xp_for_next: XP_PER_LEVEL - xp_in_level,
      percent: xp_in_level * 100.0 / XP_PER_LEVEL
    )
  end
end
