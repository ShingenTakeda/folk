source "lib/c.tcl"
source "useful/bullseye-play.tcl"

set ps [programToPs 66 "hello"]
set fd [file tempfile psfile psfile.ps]; puts $fd $ps; close $fd
exec convert $psfile -quality 300 -colorspace RGB [file rootname $psfile].jpeg
set jpegfile [file rootname $psfile].jpeg

rename [c create] ic
ic include <stdlib.h>
ic code "#undef EXTERN"
ic include <jpeglib.h>
source "pi/critclUtils.tcl"
defineImageType ic
ic proc loadImageFromJpeg {char* filename} image_t {
    struct jpeg_decompress_struct cinfo;
    struct jpeg_error_mgr jerr;
    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_decompress(&cinfo);

    FILE* f = fopen(filename, "rb");
    jpeg_stdio_src(&cinfo, f);

    if (jpeg_read_header(&cinfo, TRUE) != JPEG_HEADER_OK) { printf("Fail\n"); exit(1); }
    jpeg_start_decompress(&cinfo);

    image_t dest = (image_t) {
        .width = cinfo.output_width,
        .height = cinfo.output_height,
        .components = cinfo.output_components,
        .bytesPerRow = cinfo.output_width * cinfo.output_components,
        .data = ckalloc(cinfo.output_width * cinfo.output_height * cinfo.output_components)
    };
    
    while (cinfo.output_scanline < cinfo.output_height) {
        unsigned char *buffer_array[1];
        buffer_array[0] = dest.data + cinfo.output_scanline * dest.bytesPerRow;
        jpeg_read_scanlines(&cinfo, buffer_array, 1);
    }
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    fclose(f);
    return dest;
}
ic cflags -ljpeg
ic compile

puts [loadImageFromJpeg $jpegfile]
