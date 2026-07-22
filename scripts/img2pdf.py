#!/usr/bin/env python3

import os
import sys
from pathlib import Path

from PIL import Image
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader


image_path_prefix = "img/"
file_url_prefix = "https://github.com/milahu/alchi-journal/raw/refs/heads/main/"

# A4 dimensions in points (72 points = 1 inch)
PAGE_WIDTH, PAGE_HEIGHT = A4

# Margins reserved for header/footer
TOP_MARGIN = 36      # 0.5 inch
BOTTOM_MARGIN = 36   # 0.5 inch

# Footer settings
FOOTER_FONT = "Helvetica"
FOOTER_FONT_SIZE = 9
FOOTER_PADDING = 10


def fit_image_to_area(image_width, image_height, area_width, area_height):
    """
    Calculate the largest size that fits the image into the given area
    while preserving its aspect ratio.
    """
    scale = min(
        area_width / image_width,
        area_height / image_height,
    )

    return (
        image_width * scale,
        image_height * scale,
    )


def create_pdf(image_paths, output_path):
    pdf = canvas.Canvas(
        str(output_path),
        pagesize=A4,
    )

    workdir = os.getcwd()

    for image_path in image_paths:

        image_path = Path(image_path)

        # normalize path
        image_path = image_path.resolve().relative_to(workdir)

        assert str(image_path).startswith(image_path_prefix), \
          f"image_path {str(image_path)!r} does not start with image_path_prefix {image_path_prefix!r}"

        try:
            with Image.open(image_path) as image:
                # Convert to RGB so ReportLab/PDF handles all common
                # image formats consistently.
                if image.mode not in ("RGB", "L"):
                    image = image.convert("RGB")

                image_width, image_height = image.size

                # Area available for the scanned page.
                area_x = 0
                area_y = BOTTOM_MARGIN
                area_width = PAGE_WIDTH
                area_height = PAGE_HEIGHT - TOP_MARGIN - BOTTOM_MARGIN

                # Scale image to fit the available area while preserving
                # the original aspect ratio.
                draw_width, draw_height = fit_image_to_area(
                    image_width,
                    image_height,
                    area_width,
                    area_height,
                )

                # Center the image in the available area.
                draw_x = area_x + (area_width - draw_width) / 2
                draw_y = area_y + (area_height - draw_height) / 2

                pdf.drawImage(
                    ImageReader(image),
                    draw_x,
                    draw_y,
                    width=draw_width,
                    height=draw_height,
                    preserveAspectRatio=True,
                    mask="auto",
                )

                # Footer separator line.
                line_y = BOTTOM_MARGIN - 5

                pdf.setLineWidth(0.5)
                pdf.line(
                    20,
                    line_y,
                    PAGE_WIDTH - 20,
                    line_y,
                )

                # Footer filename.
                pdf.setFont(
                    FOOTER_FONT,
                    FOOTER_FONT_SIZE,
                )

                # filename = image_path.name
                # footer_text = filename

                # here we assume that image_path is something like
                # "img/2026-07/2026-07-21.12-50.avif"

                footer_text = file_url_prefix + str(image_path)

                r'''
                pdf.drawString(
                    20,
                    line_y - FOOTER_FONT_SIZE - FOOTER_PADDING / 2,
                    footer_text,
                )
                '''
                pdf.drawCentredString(
                    PAGE_WIDTH / 2,
                    line_y - FOOTER_FONT_SIZE - FOOTER_PADDING / 2,
                    footer_text,
                )

                pdf.showPage()

        except Exception as exc:
            print(
                f"Warning: could not process {image_path}: {exc}",
                file=sys.stderr,
            )

    pdf.save()


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {Path(sys.argv[0]).name} IMAGE1 [IMAGE2 ...]", file=sys.stderr)
        sys.exit(1)

    image_paths = sys.argv[1:]

    # Output PDF is created in the current directory.
    # output_path = Path("output.pdf")
    output_path = Path("img2pdf.pdf")

    create_pdf(image_paths, output_path)

    print(f"done {output_path}")


if __name__ == "__main__":
    main()
