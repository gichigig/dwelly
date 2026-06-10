require 'xcodeproj'
project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }
file_ref = project.main_group.find_subpath('Runner', true).files.find { |f| f.path == 'GoogleService-Info.plist' }

# Remove from Sources build phase if present
target.source_build_phase.files.each do |f|
  if f.file_ref.path == 'GoogleService-Info.plist'
    f.remove_from_project
  end
end

# Add to Resources build phase
target.resources_build_phase.add_file_reference(file_ref, true)

project.save
