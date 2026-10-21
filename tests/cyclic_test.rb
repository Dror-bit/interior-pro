# Polygon vertex zero is not a geometric invariant. Preserve winding, every
# vertex, and (when zipped with points) every edge's wall identity.
module CyclicTest
  def self.same?(actual,expected)
    actual.length==expected.length && (0...expected.length).any?{|i|actual==expected.rotate(i)}
  end
end
