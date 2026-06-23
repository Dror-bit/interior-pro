# Interior Pro — vendored solid boolean (Eneroth Solid Tools, MIT License).
# See LICENSE and solid_operations.rb.

module InteriorPro
  module SolidBoolean
    unless const_defined?(:Operations, false)
      load File.join(__dir__, 'solid_operations.rb')
      Operations = Eneroth::SolidTools::SolidOperations
    end
  end
end
