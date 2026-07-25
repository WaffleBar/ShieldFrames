using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class MakeSocialPreview
{
    const int Size = 1280;

    static readonly Color BgTop = Color.FromArgb(255, 8, 12, 18);
    static readonly Color BgBottom = Color.FromArgb(255, 14, 22, 32);
    static readonly Color TitleColor = Color.FromArgb(255, 248, 250, 252);
    static readonly Color SubtitleColor = Color.FromArgb(255, 115, 232, 255);
    static readonly Color MutedColor = Color.FromArgb(255, 136, 153, 170);
    static readonly Color HealthLight = Color.FromArgb(255, 58, 210, 72);
    static readonly Color HealthDark = Color.FromArgb(255, 26, 153, 40);
    static readonly Color ShieldColor = Color.FromArgb(115, 77, 244, 251);
    static readonly Color GlowColor = Color.FromArgb(255, 180, 250, 255);
    static readonly Color FrameColor = Color.FromArgb(255, 42, 48, 58);
    static readonly Color FrameHighlight = Color.FromArgb(255, 78, 86, 98);

    public static void Main(string[] args)
    {
        string root = args.Length > 0 ? args[0] : Directory.GetCurrentDirectory();
        string githubDir = Path.Combine(root, ".github");
        string mediaDir = Path.Combine(root, "Media");
        Directory.CreateDirectory(githubDir);
        Directory.CreateDirectory(mediaDir);

        string pngPath = Path.Combine(githubDir, "social-preview.png");
        string jpgGithubPath = Path.Combine(githubDir, "social-preview.jpg");
        string jpgPath = Path.Combine(mediaDir, "SocialPreview.jpg");
        string pngMediaPath = Path.Combine(mediaDir, "SocialPreview.png");

        using (var banner = RenderBanner(Size, Size))
        {
            banner.Save(pngPath, ImageFormat.Png);
            banner.Save(pngMediaPath, ImageFormat.Png);
            SaveJpeg(banner, jpgGithubPath, 92);
            SaveJpeg(banner, jpgPath, 92);
        }

        Console.WriteLine("Wrote " + pngPath);
        Console.WriteLine("Wrote " + jpgGithubPath);
        Console.WriteLine("Wrote " + pngMediaPath);
        Console.WriteLine("Wrote " + jpgPath);
    }

    static Bitmap RenderBanner(int width, int height)
    {
        var banner = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(banner))
        {
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            using (var bg = new LinearGradientBrush(new Rectangle(0, 0, width, height), BgTop, BgBottom, 90f))
            {
                g.FillRectangle(bg, 0, 0, width, height);
            }

            DrawAccentGlow(g, width, height);
            DrawCopy(g, width, height);
            DrawHeroBar(g, width, height);
        }

        return banner;
    }

    static void DrawAccentGlow(Graphics g, int width, int height)
    {
        using (var path = new GraphicsPath())
        {
            path.AddEllipse(width * 0.08f, height * 0.34f, width * 0.84f, height * 0.42f);
            using (var brush = new PathGradientBrush(path))
            {
                brush.CenterColor = Color.FromArgb(42, 77, 244, 251);
                brush.SurroundColors = new[] { Color.FromArgb(0, 77, 244, 251) };
                g.FillPath(brush, path);
            }
        }
    }

    static void DrawCopy(Graphics g, int width, int height)
    {
        using (var titleFont = new Font("Segoe UI", 92f, FontStyle.Bold, GraphicsUnit.Pixel))
        using (var subtitleFont = new Font("Segoe UI", 34f, FontStyle.Regular, GraphicsUnit.Pixel))
        using (var detailFont = new Font("Segoe UI", 24f, FontStyle.Regular, GraphicsUnit.Pixel))
        using (var creditFont = new Font("Segoe UI", 20f, FontStyle.Regular, GraphicsUnit.Pixel))
        using (var titleBrush = new SolidBrush(TitleColor))
        using (var subtitleBrush = new SolidBrush(SubtitleColor))
        using (var detailBrush = new SolidBrush(MutedColor))
        {
            DrawCentered(g, "ShieldFrames", titleFont, titleBrush, width, 118f);
            DrawCentered(g, "Overshield overlay", subtitleFont, subtitleBrush, width, 228f);
            DrawCentered(g, "for Blizzard unit frames", subtitleFont, subtitleBrush, width, 272f);
            DrawCentered(g, "Player  ·  Target  ·  Party  ·  Raid", detailFont, detailBrush, width, height - 72f);
            DrawCentered(g, "By Burn and Waffle", creditFont, detailBrush, width, height - 40f);
        }
    }

    static void DrawCentered(Graphics g, string text, Font font, Brush brush, int width, float y)
    {
        SizeF size = g.MeasureString(text, font);
        g.DrawString(text, font, brush, (width - size.Width) / 2f, y);
    }

    static void DrawHeroBar(Graphics g, int width, int height)
    {
        float barWidth = width * 0.78f;
        float barHeight = 118f;
        float x = (width - barWidth) / 2f;
        float y = height * 0.46f;
        float radius = 12f;
        float frame = 5f;
        float healthRatio = 0.62f;

        var outer = new RectangleF(x, y, barWidth, barHeight);
        var inner = RectangleF.Inflate(outer, -frame, -frame);
        float healthWidth = inner.Width * healthRatio;
        var healthRect = new RectangleF(inner.X, inner.Y, healthWidth, inner.Height);
        var shieldRect = new RectangleF(inner.X + healthWidth, inner.Y, inner.Width - healthWidth, inner.Height);

        using (var framePath = RoundedRect(outer, radius))
        using (var frameBrush = new SolidBrush(FrameColor))
        using (var frameBorder = new Pen(FrameHighlight, 2f))
        {
            g.FillPath(frameBrush, framePath);
            g.DrawPath(frameBorder, framePath);
        }

        using (var clip = RoundedRect(inner, radius - 2f))
        {
            g.SetClip(clip);

            using (var healthBrush = new LinearGradientBrush(healthRect, HealthLight, HealthDark, LinearGradientMode.Vertical))
            {
                g.FillRectangle(healthBrush, healthRect);
            }

            using (var shieldBrush = new SolidBrush(ShieldColor))
            {
                g.FillRectangle(shieldBrush, shieldRect);
            }

            DrawStripes(g, shieldRect);
            DrawGlowEdge(g, shieldRect.X, inner.Y, inner.Height);

            g.ResetClip();
        }

        DrawBarLabel(g, "Health", healthRect, Color.FromArgb(230, 255, 255, 255));
        DrawBarLabel(g, "Overshield", shieldRect, Color.FromArgb(230, 220, 250, 255));
    }

    static void DrawStripes(Graphics g, RectangleF rect)
    {
        using (var pen = new Pen(Color.FromArgb(70, 255, 255, 255), 3f))
        {
            for (float offset = rect.Left - rect.Height; offset < rect.Right + rect.Height; offset += 18f)
            {
                g.DrawLine(pen, offset, rect.Bottom, offset + rect.Height, rect.Top);
            }
        }
    }

    static void DrawGlowEdge(Graphics g, float x, float y, float barHeight)
    {
        using (var glowBrush = new LinearGradientBrush(
            new RectangleF(x - 12f, y, 24f, barHeight),
            Color.FromArgb(0, GlowColor),
            GlowColor,
            LinearGradientMode.Horizontal))
        {
            g.FillRectangle(glowBrush, x - 12f, y, 24f, barHeight);
        }

        using (var corePen = new Pen(GlowColor, 4f))
        {
            g.DrawLine(corePen, x, y + 6f, x, y + barHeight - 6f);
        }
    }

    static void DrawBarLabel(Graphics g, string text, RectangleF rect, Color color)
    {
        using (var font = new Font("Segoe UI Semibold", 22f, FontStyle.Bold, GraphicsUnit.Pixel))
        using (var brush = new SolidBrush(color))
        {
            var size = g.MeasureString(text, font);
            g.DrawString(text, font, brush, rect.X + 18f, rect.Y + (rect.Height - size.Height) / 2f);
        }
    }

    static GraphicsPath RoundedRect(RectangleF bounds, float radius)
    {
        var path = new GraphicsPath();
        float d = radius * 2f;
        path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
        path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
        path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    static void SaveJpeg(Bitmap source, string path, long quality)
    {
        var codec = GetEncoder(ImageFormat.Jpeg);
        using (var encoderParams = new EncoderParameters(1))
        {
            encoderParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
            source.Save(path, codec, encoderParams);
        }
    }

    static ImageCodecInfo GetEncoder(ImageFormat format)
    {
        ImageCodecInfo[] codecs = ImageCodecInfo.GetImageDecoders();
        foreach (ImageCodecInfo codec in codecs)
        {
            if (codec.FormatID == format.Guid)
            {
                return codec;
            }
        }

        throw new InvalidOperationException("JPEG encoder not found.");
    }
}
