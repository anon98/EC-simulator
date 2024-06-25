function cleanup_images()
    # Specify the directory where images are stored
    image_directory = "outputs/images_EC"
    
    # Check if the directory exists
    if isdir(image_directory)
        println("Cleaning up images...")
        
        # Get a list of all files and directories under 'output/images'
        files = readdir(image_directory)
        
        # Iterate through each file/directory and delete them
        for file in files
            full_path = joinpath(image_directory, file)
            
            # Check if it's a file or directory and delete accordingly
            if isfile(full_path)
                println("Deleting file: $file")
                rm(full_path)  # Delete file
            elseif isdir(full_path)
                println("Deleting directory: $file")
                rm(full_path; recursive=true)  # Delete directory recursively
            end
        end
        
        println("Cleanup complete.")
    else
        println("Image directory '$image_directory' not found.")
    end
end
