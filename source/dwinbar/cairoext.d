module dwinbar.cairoext;

import cairo.cairo;
import std.math;

void roundedRectangle(Context ctx, double x, double y, double width, double height,
	double cornerRadius, double aspect = 1)
{
	double radius = cornerRadius / aspect;
	double degrees = PI / 180.0;
	ctx.newSubPath();
	ctx.arc(x + width - radius, y + radius, radius, -90 * degrees, 0 * degrees);
	ctx.arc(x + width - radius, y + height - radius, radius, 0 * degrees, 90 * degrees);
	ctx.arc(x + radius, y + height - radius, radius, 90 * degrees, 180 * degrees);
	ctx.arc(x + radius, y + radius, radius, 180 * degrees, 270 * degrees);
	ctx.closePath();
}
