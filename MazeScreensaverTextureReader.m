function MazeScreensaverTextureReader(inputFilename, generateColormapAndIndexImage)
% Reads an indexed-color bitmap extracted from the Windows 95 3D maze screensaver executable.
% Written during development of my PROCJAM 2017 submission, "Screensaver Subterfuge" (https://poor-track-design.itch.io/screensaver-subterfuge).
% I used ResourcesExtract (https://www.nirsoft.net/utils/resources_extract.html) to extract the bitmaps from the 3D maze executable.
% HxD (https://mh-nexus.de/en/hxd/) was quite useful when figuring out the format of the bitmaps.
%
% Although written in MATLAB, this script is compatible with Octave (https://www.gnu.org/software/octave/). It runs slower in Octave, however.
%
% Parameters:
% - inputFilePath: name of input file. Should be in the same directory as this script.
% - generateColormapAndIndexImage: true or false. Useful for the fractal-esque pattern textures, which are meant to be color-cycled.
%
% Most of the 3D maze texture bitmaps use a variant of the 8-bit run-length encoding (RLE) documented here:
% https://docs.microsoft.com/en-us/windows/desktop/gdi/bitmap-compression
%
% Main differences:
% - No "end of line" sequence (00 00) in encoded mode. Line termination is based on the image dimensions.
% - In absolute mode, the "number of bytes to follow" byte is two greater than the number of following bytes. This is 
%   presumably to distinguish it from the "delta" encoded mode sequence (00 02), which allows absolute mode to specify a 
%   run of one or two pixels (something not possible with the documented 8-bit RLE method). Somewhat pointless, as two 
%   distinct pixels can be specified using encoded mode in the same number of bytes (four) and a single pixel can be 
%   specified in two bytes using encoded mode vs. three in absolute mode.
%
% Textures this script can read (file names are those assigned by ResourcesExtract):
% - 3D Maze - Copy_103_101.bin (start button)
% - 3D Maze - Copy_104_101.bin (smiley face)
% - 3D Maze - Copy_105_101.bin (rat)
% - 3D Maze - Copy_106_101.bin (OpenGL text)
% - 3D Maze - Copy_120_101.bin (pattern 1)
% - 3D Maze - Copy_121_101.bin (pattern 2)
% - 3D Maze - Copy_125_101.bin (pattern 3)
% - 3D Maze - Copy_127_101.bin (pattern 4)
%
% Note that the following 3D maze textures are regular bitmaps (this script won't read them) and can be opened with GIMP or other image editors:
% - 3D Maze - Copy_100_100.bin (brick)
% - 3D Maze - Copy_101_100.bin (carpet)
% - 3D Maze - Copy_102_100.bin (stone)
% - 3D Maze - Copy_107_100.bin (OpenGL demo image used on the cover of the OpenGL Programming Guide)

% All offsets in comments are specified in decimal. In code, one is added to offsets since MATLAB uses one-based indexing.

fileID = fopen(inputFilename, 'r');
data = fread(fileID);
fclose(fileID);

% Bytes at offsets 4 and 5 contain width or height of image (little-endian).
% Bytes at offsets 9 and 10 contain height or width.
% The 3D maze textures are square, so this script just reads the bytes at offsets 4 and 5.
% e.g., 0x80 0x00 => 0x0080 = 128
% e.g., 0x00 0x01 => 0x0100 = 256
dim = data(5) + data(6)*16^2;

% Bitmaps are indexed color.
bytesPerPixel = 4; % Order is BGRA (informed guess; an order commonly used by Microsoft).
tableCount = 256; % Another informed guess; also based on inspection (all the pattern textures use the same color table; very handy).
offset = 24; % Bytes; offset to start of color table.

table = [];
for i = (1 + offset):bytesPerPixel:(bytesPerPixel*tableCount + offset)
    val = [data(i) data(i+1) data(i+2) data(i+3)];
    table = cat(1, table, reshape(val([3 2 1 4]), 1, 1, 4));
end

colorZero = table(1, 1, :); % First color in color table. Has an alpha of 0 for the textures with transparent regions.

% All pixels are initialized to the color at index 0 in the color table. See note about delta sequence below.
new = repmat(colorZero(:,:,1:3), dim, dim);
newAlpha = zeros(dim, dim, 1);
newIndex = zeros(dim, dim);

row = 1;
col = 1;
startByte = (bytesPerPixel*tableCount + offset + 1);
i = startByte;
while i <= numel(data)
    val = data(i);
    
    if val == 0
        % Note that the EOL encoded mode sequence (00 00) is not used in this format.
        % (The EOL sequence is part of the 8-bit RLE format documented here: https://docs.microsoft.com/en-us/windows/desktop/gdi/bitmap-compression)
        if data(i+1) == 1 % Encoded mode: EOF 00 01
            disp('END OF FILE');
            break;
        elseif data(i+1) == 2 % Encoded mode: DELTA 00 02 dX dY (seems that skipped pixels should be assigned color with index 0; handled during initialization above)
            deltaX = data(i+2);
            deltaY = data(i+3);
            row = row + deltaY;
            col = col + deltaX;
            if col > dim % You'd expect that this would be the result of an invalid delta sequence, but it occurs once in the OpenGL bitmap.
               col = 1; 
            end
            i = i+4;
            continue;
        elseif data(i+1) >= 3 && data(i+1) <= 255 % Absolute mode: 00 # index index index ...
            remainingPixelsInRun = data(i+1) - 2; % Regarding the subtraction of two, see notes at top of file.
            i = i+2;
            while (remainingPixelsInRun > 0)
                val = data(i);
                pixelIndex = val + 1; % Current value is index into color table; MATLAB uses 1-based indexing.
                
                color = [table(pixelIndex, 1, 1) table(pixelIndex, 1, 2) table(pixelIndex, 1, 3) table(pixelIndex, 1, 4)];
                new(row, col, 1) = color(1);
                new(row, col, 2) = color(2);
                new(row, col, 3) = color(3);

                newAlpha(row, col,1) = color(4);
                
                newIndex(row, col, 1) = pixelIndex;

                col = col + 1;

                if col > dim
                    row = row + 1;
                    col = 1;
                end
                
                remainingPixelsInRun = remainingPixelsInRun - 1;
                i = i + 1;
            end
            continue;
        end
    end
    
    % Encoded mode
    numPixels = val;
    pixelIndex = data(i+1) + 1; % MATLAB 1-based indexing, hence +1.
    i = i + 2; % Skip over the pixelIndex byte
    for curPixel = 1:numPixels
        color = [table(pixelIndex, 1, 1) table(pixelIndex, 1, 2) table(pixelIndex, 1, 3) table(pixelIndex, 1, 4)];
        new(row, col, 1) = color(1);
        new(row, col, 2) = color(2);
        new(row, col, 3) = color(3);

        newAlpha(row, col,1) = color(4);
        
        newIndex(row, col, 1) = pixelIndex;

        col = col + 1;
        
        if col > dim
            row = row + 1;
            col = 1;
        end
    end
end

% Display images
% These are vertically mirrored because bitmaps start in the bottom-left (hence the calls to flipdim() in the output code below).
% Top and bottom of images are cut off when displayed in some versions of Octave (fine in MATLAB). Output is still correct.
% Presumably the implementations of image() and imagesc() in some Octave versions aren't equivalent to those in MATLAB.

figure
image(uint8(new));
axis equal;
title('Image (RGB)');

figure
imagesc(uint8(newAlpha),[0,255]);
colormap('gray');
axis equal;
title('Image (A)');

if generateColormapAndIndexImage
    figure
    image(uint8(table(:,:,1:3)));
    axis equal; % Incorrect, but easier to view.
    title('Color Table');
    
    figure
    imagesc(uint8(newIndex),[0,255]);
    colormap('gray');
    axis equal;
    title('Image (grayscale)');
end

% Output

imwrite(flipdim(uint8(new), 1), [inputFilename(1:end-4) '_image.png'], 'Alpha', flipdim(uint8(newAlpha), 1));

if generateColormapAndIndexImage
    imwrite(uint8(table(:,:,1:3)), [inputFilename(1:end-4) '_color_table.png']);
    imwrite(flipdim(uint8(newIndex), 1), [inputFilename(1:end-4) '_image_grayscale.png']);
end

end

