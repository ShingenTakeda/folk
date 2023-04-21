source "lib/c.tcl"
source "pi/cUtils.tcl"

rename [c create] camc

camc include <string.h>
camc include <math.h>

camc include <errno.h>
camc include <fcntl.h>
camc include <sys/ioctl.h>
camc include <sys/mman.h>
camc include <asm/types.h>
camc include <linux/videodev2.h>

camc include <stdint.h>
camc include <stdlib.h>

camc include <jpeglib.h>

camc struct buffer_t {
    uint8_t* start;
    size_t length;
}
camc struct camera_t {
    int fd;
    uint32_t width;
    uint32_t height;
    size_t buffer_count;
    buffer_t* buffers;
    buffer_t head;
}

camc code {
    void quit(const char* msg) {
        fprintf(stderr, "[%s] %d: %s\n", msg, errno, strerror(errno));
        exit(1);
    }

    int xioctl(int fd, int request, void* arg) {
        for (int i = 0; i < 100; i++) {
            int r = ioctl(fd, request, arg);
            if (r != -1 || errno != EINTR) return r;
            printf("[%x][%d] %s\n", request, i, strerror(errno));
        }
        return -1;
    }
}
defineImageType camc

camc proc cameraOpen {char* device int width int height} camera_t* {
    printf("device [%s]\n", device);
    int fd = open(device, O_RDWR | O_NONBLOCK, 0);
    if (fd == -1) quit("open");
    camera_t* camera = malloc(sizeof (camera_t));
    camera->fd = fd;
    camera->width = width;
    camera->height = height;
    camera->buffer_count = 0;
    camera->buffers = NULL;
    camera->head.length = 0;
    camera->head.start = NULL;
    return camera;
}
    
camc proc cameraInit {camera_t* camera} void {
    struct v4l2_capability cap;
    if (xioctl(camera->fd, VIDIOC_QUERYCAP, &cap) == -1) quit("VIDIOC_QUERYCAP");
    if (!(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE)) quit("no capture");
    if (!(cap.capabilities & V4L2_CAP_STREAMING)) quit("no streaming");

    struct v4l2_format format;
    memset(&format, 0, sizeof format);
    format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    format.fmt.pix.width = camera->width;
    format.fmt.pix.height = camera->height;
    format.fmt.pix.pixelformat = V4L2_PIX_FMT_MJPEG;
    format.fmt.pix.field = V4L2_FIELD_NONE;
    if (xioctl(camera->fd, VIDIOC_S_FMT, &format) == -1) quit("VIDIOC_S_FMT");

    struct v4l2_requestbuffers req;
    memset(&req, 0, sizeof req);
    req.count = 4;
    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_MMAP;
    if (xioctl(camera->fd, VIDIOC_REQBUFS, &req) == -1) quit("VIDIOC_REQBUFS");
    camera->buffer_count = req.count;
    camera->buffers = calloc(req.count, sizeof (buffer_t));

    size_t buf_max = 0;
    for (size_t i = 0; i < camera->buffer_count; i++) {
        struct v4l2_buffer buf;
        memset(&buf, 0, sizeof buf);
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = i;
        if (xioctl(camera->fd, VIDIOC_QUERYBUF, &buf) == -1)
            quit("VIDIOC_QUERYBUF");
        if (buf.length > buf_max) buf_max = buf.length;
        camera->buffers[i].length = buf.length;
        camera->buffers[i].start = 
            mmap(NULL, buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, 
                 camera->fd, buf.m.offset);
        if (camera->buffers[i].start == MAP_FAILED) quit("mmap");
    }
    camera->head.start = malloc(buf_max);

    printf("camera %d; bufcount %zu\n", camera->fd, camera->buffer_count);
}

camc proc cameraStart {camera_t* camera} void {
    for (size_t i = 0; i < camera->buffer_count; i++) {
        struct v4l2_buffer buf;
        memset(&buf, 0, sizeof buf);
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = i;
        if (xioctl(camera->fd, VIDIOC_QBUF, &buf) == -1) quit("VIDIOC_QBUF");
        printf("camera_start(%zu): %s\n", i, strerror(errno));
    }

    enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (xioctl(camera->fd, VIDIOC_STREAMON, &type) == -1) 
        quit("VIDIOC_STREAMON");
}

camc code {
int camera_capture(camera_t* camera) {
    struct v4l2_buffer buf;
    memset(&buf, 0, sizeof buf);
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    if (xioctl(camera->fd, VIDIOC_DQBUF, &buf) == -1) {
        fprintf(stderr, "camera_capture: VIDIOC_DQBUF failed: %d: %s\n", errno, strerror(errno));
        return 0;
    }
    memcpy(camera->head.start, camera->buffers[buf.index].start, buf.bytesused);
    camera->head.length = buf.bytesused;
    if (xioctl(camera->fd, VIDIOC_QBUF, &buf) == -1) {
        fprintf(stderr, "camera_capture: VIDIOC_QBUF failed: %d: %s\n", errno, strerror(errno));
        return 0;
    }
    return 1;
}
}

camc proc cameraFrame {camera_t* camera} int {
    struct timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;

    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(camera->fd, &fds);
    int r = select(camera->fd + 1, &fds, 0, 0, &timeout);
    // printf("r: %d\n", r);
    if (r == -1) quit("select");
    if (r == 0) {
        printf("selection failed of fd %d\n", camera->fd);
        return 0;
    }
    return camera_capture(camera);
}

camc proc cameraDecompressRgb {camera_t* camera image_t dest} void {
      struct jpeg_decompress_struct cinfo;
      struct jpeg_error_mgr jerr;
      cinfo.err = jpeg_std_error(&jerr);
      jpeg_create_decompress(&cinfo);
      jpeg_mem_src(&cinfo, camera->head.start, camera->head.length);
      if (jpeg_read_header(&cinfo, TRUE) != 1) {
          printf("Fail\n");
          exit(1);
      }
      jpeg_start_decompress(&cinfo);

      while (cinfo.output_scanline < cinfo.output_height) {
          unsigned char *buffer_array[1];
          buffer_array[0] = dest.data + (cinfo.output_scanline) * dest.width * cinfo.output_components;
          jpeg_read_scanlines(&cinfo, buffer_array, 1);
      }
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
}
camc proc cameraDecompressGray {camera_t* camera image_t dest} void {
      struct jpeg_decompress_struct cinfo;
      struct jpeg_error_mgr jerr;
      cinfo.err = jpeg_std_error(&jerr);
      jpeg_create_decompress(&cinfo);
      jpeg_mem_src(&cinfo, camera->head.start, camera->head.length);
      if (jpeg_read_header(&cinfo, TRUE) != 1) {
          printf("Fail\n");
          exit(1);
      }
      cinfo.out_color_space = JCS_GRAYSCALE;
      jpeg_start_decompress(&cinfo);

      while (cinfo.output_scanline < cinfo.output_height) {
          unsigned char *buffer_array[1];
          buffer_array[0] = dest.data + (cinfo.output_scanline) * dest.width * cinfo.output_components;
          jpeg_read_scanlines(&cinfo, buffer_array, 1);
      }
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
}
camc proc rgbToGray {image_t rgb} image_t {
    uint8_t* gray = calloc(rgb.width * rgb.height, sizeof (uint8_t));
    for (int y = 0; y < rgb.height; y++) {
        for (int x = 0; x < rgb.width; x++) {
            // we're spending 10-20% of camera time here on Pi ... ??

            int i = (y * rgb.width + x) * 3;
            uint32_t r = rgb.data[i];
            uint32_t g = rgb.data[i + 1];
            uint32_t b = rgb.data[i + 2];
            // from https://mina86.com/2021/rgb-to-greyscale/
            uint32_t yy = 3567664 * r + 11998547 * g + 1211005 * b;
            gray[y * rgb.width + x] = ((yy + (1 << 23)) >> 24);
        }
    }
    return (image_t) {
        .width = rgb.width, .height = rgb.height,
        .bytesPerRow = rgb.width,
        .data = gray
    };
}
camc proc thresholdGray {image_t gray} image_t {
    uint8_t* newGray = calloc(gray.width * gray.height, sizeof (uint8_t));
    for (int y = 0; y < gray.height; y++) {
        for (int x = 0; x < gray.width; x++) {
            int i = (y * gray.width + x) * 1;
            uint8_t g = gray.data[i];
            if (g > 128) {
                g = 255;
            } else {
                g = 0;
            }
            newGray[y * gray.width + x] = g;
        }
    }
    return (image_t) {
        .width = gray.width, .height = gray.height,
        .bytesPerRow = gray.width,
        .data = newGray
    };
}
camc proc freeUint8Buffer {uint8_t* buf} void {
    free(buf);
}

camc proc newImage {int width int height int components} image_t {
    return (image_t) { width, height, components, width*components, malloc(width*height*components) };
}
camc proc freeImage {image_t image} void {
    free(image.data);
}

# On one of my RPi, path needs to be changed to /sbin/ldconfig
c loadlib [expr {$tcl_platform(os) eq "Darwin" ? "/opt/homebrew/lib/libjpeg.dylib" : [lindex [exec /usr/sbin/ldconfig -p | grep libjpeg] end]}]
camc compile

namespace eval Camera {
    variable camera

    variable WIDTH
    variable HEIGHT

    proc init {width height} {
        variable WIDTH
        variable HEIGHT
        set WIDTH $width
        set HEIGHT $height
        
        set camera [cameraOpen "/dev/video0" $WIDTH $HEIGHT]
        cameraInit $camera
        cameraStart $camera
        
        # skip 5 frames for booting a cam
        for {set i 0} {$i < 5} {incr i} {
            cameraFrame $camera
        }
        set Camera::camera $camera
    }

    proc frame {} {
        variable camera
        variable WIDTH; variable HEIGHT
        if {![cameraFrame $camera]} {
            error "Failed to capture from camera"
        }
        set image [newImage $WIDTH $HEIGHT 3]
        cameraDecompressRgb $camera $image
        set image
    }
    proc grayFrame {} {
        variable camera
        variable WIDTH; variable HEIGHT
        if {![cameraFrame $camera]} {
            error "Failed to capture from camera"
        }
        set image [newImage $WIDTH $HEIGHT 1]
        cameraDecompressGray $camera $image
        set image
    }
}

if {([info exists ::argv0] && $::argv0 eq [info script]) || \
        ([info exists ::entry] && $::entry == "pi/Camera.tcl")} {
    source pi/Display.tcl
    Display::init

    # Camera::init 3840 2160
    Camera::init 1280 720
    # Camera::init 1920 1080
    puts "camera: $Camera::camera"

    while true {
        set rgb [Camera::frame]
        set gray [rgbToGray $rgb]
        set gray2 [thresholdGray $gray]
        # FIXME: hacky
        Display::grayImage $Display::fb $Display::WIDTH $Display::HEIGHT "(uint8_t*) [dict get $gray2 data]" $Camera::WIDTH $Camera::HEIGHT
        freeImage $gray2
        freeImage $gray
        freeImage $rgb
    }
}


namespace eval AprilTags {
    rename [c create] apc
    apc cflags -I$::env(HOME)/apriltag
    apc include <apriltag.h>
    apc include <tagStandard52h13.h>
    apc include <math.h>
    apc include <assert.h>
    apc code {
        apriltag_detector_t *td;
        apriltag_family_t *tf;
    }
    defineImageType apc

    apc proc detectInit {} void {
        td = apriltag_detector_create();
        tf = tagStandard52h13_create();
        apriltag_detector_add_family_bits(td, tf, 1);
        td->nthreads = 2;
    }

    apc proc detect {image_t gray} Tcl_Obj* {
        assert(gray.components == 1);
        image_u8_t im = (image_u8_t) { .width = gray.width, .height = gray.height, .stride = gray.width, .buf = gray.data };
    
        zarray_t *detections = apriltag_detector_detect(td, &im);
        int detectionCount = zarray_size(detections);

        Tcl_Obj* detectionObjs[detectionCount];
        for (int i = 0; i < detectionCount; i++) {
            apriltag_detection_t *det;
            zarray_get(detections, i, &det);

            int size = sqrt((det->p[0][0] - det->p[1][0])*(det->p[0][0] - det->p[1][0]) + (det->p[0][1] - det->p[1][1])*(det->p[0][1] - det->p[1][1]));
            detectionObjs[i] = Tcl_ObjPrintf("id %d center {%f %f} corners {{%f %f} {%f %f} {%f %f} {%f %f}} size %d",
                                             det->id,
                                             det->c[0], det->c[1],
                                             det->p[0][0], det->p[0][1],
                                             det->p[1][0], det->p[1][1],
                                             det->p[2][0], det->p[2][1],
                                             det->p[3][0], det->p[3][1],
                                             size);
        }
        

        zarray_destroy(detections);
        Tcl_Obj* result = Tcl_NewListObj(detectionCount, detectionObjs);
        return result;
    }

    apc proc detectCleanup {} void {
        tagStandard52h13_destroy(tf);
        apriltag_detector_destroy(td);
    }

    c loadlib $::env(HOME)/apriltag/libapriltag.so
    apc compile
    
    proc init {} {
        detectInit
    }
}


namespace eval LaserBlobTracker {
    rename [c create] apc
    apc cflags -I$::env(HOME)/apriltag
    apc include <apriltag.h>
    apc include <math.h>
    apc include <assert.h>
    apc code {
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "hk.h"

// Note from Haip: code copied from https://www.ocf.berkeley.edu/~fricke/projects/hoshenkopelman/hk.c
// because I haven't figure out where I could import this file from
// https://www.ocf.berkeley.edu/~fricke/projects/hoshenkopelman/hoshenkopelman.html

/* Implementation of Union-Find Algorithm */


/* The 'labels' array has the meaning that labels[x] is an alias for the label x; by
   following this chain until x == labels[x], you can find the canonical name of an
   equivalence class.  The labels start at one; labels[0] is a special value indicating
   the highest label already used. */

int *labels;
int  n_labels = 0;     /* length of the labels array */

/*  uf_find returns the canonical label for the equivalence class containing x */

int uf_find(int x) {
  int y = x;
  while (labels[y] != y)
    y = labels[y];
  
  while (labels[x] != x) {
    int z = labels[x];
    labels[x] = y;
    x = z;
  }
  return y;
}

/*  uf_union joins two equivalence classes and returns the canonical label of the resulting class. */

int uf_union(int x, int y) {
  return labels[uf_find(x)] = uf_find(y);
}

/*  uf_make_set creates a new equivalence class and returns its label */

int uf_make_set(void) {
  labels[0] ++;
  assert(labels[0] < n_labels);
  labels[labels[0]] = labels[0];
  return labels[0];
}

/*  uf_intitialize sets up the data structures needed by the union-find implementation. */

void uf_initialize(int max_labels) {
  n_labels = max_labels;
  labels = calloc(sizeof(int), n_labels);
  labels[0] = 0;
}

/*  uf_done frees the memory used by the union-find data structures */

void uf_done(void) {
  n_labels = 0;
  free(labels);
  labels = 0;
}

/* End Union-Find implementation */

#define max(a,b) (a>b?a:b)
#define min(a,b) (a>b?b:a)

/* Label the clusters in "matrix".  Return the total number of clusters found. */

int hoshen_kopelman(int **matrix, int m, int n) {
  
  uf_initialize(m * n / 2);
  
  /* scan the matrix */
  
  for (int i=0; i<m; i++)
    for (int j=0; j<n; j++)
      if (matrix[i][j]) {                        // if occupied ...

	int up = (i==0 ? 0 : matrix[i-1][j]);    //  look up  
	int left = (j==0 ? 0 : matrix[i][j-1]);  //  look left
	
	switch (!!up + !!left) {
	  
	case 0:
	  matrix[i][j] = uf_make_set();      // a new cluster
	  break;
	  
	case 1:                              // part of an existing cluster
	  matrix[i][j] = max(up,left);       // whichever is nonzero is labelled
	  break;
	  
	case 2:                              // this site binds two clusters
	  matrix[i][j] = uf_union(up, left);
	  break;
	}
	
      }
  
  /* apply the relabeling to the matrix */

  /* This is a little bit sneaky.. we create a mapping from the canonical labels
     determined by union/find into a new set of canonical labels, which are 
     guaranteed to be sequential. */
  
  int *new_labels = calloc(sizeof(int), n_labels); // allocate array, initialized to zero
  
  for (int i=0; i<m; i++)
    for (int j=0; j<n; j++)
      if (matrix[i][j]) {
	int x = uf_find(matrix[i][j]);
	if (new_labels[x] == 0) {
	  new_labels[0]++;
	  new_labels[x] = new_labels[0];
	}
	matrix[i][j] = new_labels[x];
      }
 
  int total_clusters = new_labels[0];

  free(new_labels);
  uf_done();

  return total_clusters;
}
    }
    apc code {
        typedef struct {
            int id;

            // The center of the detection in image pixel coordinates.
            double c[2];

            // The corners of the tag in image pixel coordinates. These always
            // wrap counter-clock wise around the tag.
            // TL BL BR TR
            double p[4][2];

            int size;
        } detected_blob_t;

        zarray_t *blob_detector_detect(image_u8_t *im_orig)
        {
            zarray_t *detections = zarray_create(sizeof(detected_blob_t*));

            // m = rows, n = columns
            int m = im_orig->height;
            int n = im_orig->width;
            int **matrix;
            matrix = (int **)malloc(m * sizeof(int *));
            for(int i = 0; i < m; i++)
                matrix[i] = (int *)malloc(n * sizeof(int));

            // for(int i = 0; i < rows; i++)
            //     memset(matrix[i], 0, cols * sizeof(int));
            
            for (int y = 0; y < im_orig->height; y++) {
                for (int x = 0; x < im_orig->width; x++) {
                    int i = y * im_orig->stride + x;
                    int v = im_orig->buf[i];

                    // threshold
                    if (v > 128) {
                        v = 1;
                    } else {
                        v = 0;
                    }
                    matrix[y][x] = v;
                }
            }

            int clusters = hoshen_kopelman(matrix,m,n);
            // printf("clusters: %d\n", clusters);

            for (int i=0; i<clusters; i++) {
                detected_blob_t *det = calloc(1, sizeof(detected_blob_t));
                det->id = i;
                det->c[0] = 0;
                det->c[1] = 0;
                det->p[0][0] = 0;
                det->p[0][1] = 0;
                det->p[1][0] = 0;
                det->p[1][1] = 0;
                det->p[2][0] = 0;
                det->p[2][1] = 0;
                det->p[3][0] = 0;
                det->p[3][1] = 0;
                det->size = 0;
                zarray_add(detections, &det);
            }

            for (int i=0; i<m; i++) {
                for (int j=0; j<n; j++) {
                    // printf("%d ",matrix[i][j]); 
                    if (matrix[i][j]) {
                        detected_blob_t *det;
                        zarray_get(detections, matrix[i][j]-1, &det);
                        det->c[0] += j;
                        det->c[1] += i;
                        det->size += 1;
                    }
                }
                // printf("\n");
            }

            for (int i=0; i<clusters; i++) {
                detected_blob_t *det;
                zarray_get(detections, i, &det);
                det->id = i;
                det->c[0] = det->c[0] / det->size;
                det->c[1] = det->c[1] / det->size;
            }

            for (int i=0; i<m; i++)
                free(matrix[i]);
            free(matrix);

            return detections;
        }

        void blob_detection_destroy(detected_blob_t *det)
        {
            if (det == NULL)
                return;

            free(det);
        }

        void blob_detections_destroy(zarray_t *detections)
        {
            for (int i = 0; i < zarray_size(detections); i++) {
                detected_blob_t *det;
                zarray_get(detections, i, &det);

                blob_detection_destroy(det);
            }

            zarray_destroy(detections);
        }
    }
    defineImageType apc

    apc proc detect {image_t gray} Tcl_Obj* {
        assert(gray.components == 1);
        image_u8_t im = (image_u8_t) { .width = gray.width, .height = gray.height, .stride = gray.width, .buf = gray.data };

        zarray_t *detections = blob_detector_detect(&im);
        int detectionCount = zarray_size(detections);

        Tcl_Obj* detectionObjs[detectionCount];
        for (int i = 0; i < detectionCount; i++) {
            detected_blob_t *det;
            zarray_get(detections, i, &det);

            // printf("detection %3d: id %-4d\n cx %f cy %f size %d\n", i, det->id, det->c[0], det->c[1], det->size);

            // int size = sqrt((det->p[0][0] - det->p[1][0])*(det->p[0][0] - det->p[1][0]) + (det->p[0][1] - det->p[1][1])*(det->p[0][1] - det->p[1][1]));
            int size = det->size;
            detectionObjs[i] = Tcl_ObjPrintf("id %d center {%f %f} corners {{%f %f} {%f %f} {%f %f} {%f %f}} size %d",
                                             det->id,
                                             det->c[0], det->c[1],
                                             det->p[0][0], det->p[0][1],
                                             det->p[1][0], det->p[1][1],
                                             det->p[2][0], det->p[2][1],
                                             det->p[3][0], det->p[3][1],
                                             size);
        }

        blob_detections_destroy(detections);
        
        Tcl_Obj* result = Tcl_NewListObj(detectionCount, detectionObjs);
        return result;
    }

    apc compile
}