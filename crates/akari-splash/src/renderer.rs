use std::path::Path;

use ab_glyph::{Font, FontVec, PxScale, ScaleFont, VariableFont, point};
use tiny_skia::{Color, FilterQuality, Paint, PathBuilder, Pixmap, PixmapPaint, Transform};

use crate::Result;

pub struct Renderer {
    avatar: Pixmap,
    font: FontVec,
}

#[derive(Clone, Copy, Debug)]
pub struct DirtyRect {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

/// Each output owns its layout and scaled image. Animation only composites
/// these cached layers; PNG decoding and glyph rasterization never run per frame.
pub struct Scene {
    background: Pixmap,
    avatar: Pixmap,
    pixels: Pixmap,
    dirty_rects: Vec<DirtyRect>,
    scale: f32,
    avatar_y: f32,
    dots_x: f32,
    dots_y: f32,
}

impl Renderer {
    pub fn load() -> Result<Self> {
        let avatar = Pixmap::decode_png(include_bytes!("../assets/akari-avatar.png"))?;
        let mut font = FontVec::try_from_vec(include_bytes!("../assets/Quicksand.ttf").to_vec())?;
        font.set_variation(b"wght", 500.0);
        Ok(Self { avatar, font })
    }

    pub fn create_scene(&self, width: u32, height: u32, dark: bool) -> Result<Scene> {
        let mut background = Pixmap::new(width, height).ok_or("invalid output dimensions")?;
        let (base, foreground, muted) = if dark {
            ([0, 0, 0], [224, 207, 220], [159, 141, 159])
        } else {
            ([250, 247, 242], [99, 81, 101], [160, 139, 153])
        };
        background.fill(Color::from_rgba8(base[0], base[1], base[2], 255));
        let scale = (width as f32 / 1128.0).min(height as f32 / 760.0);
        let size = (272.0 * scale).round().max(1.0) as u32;
        let mut avatar = Pixmap::new(size, size).ok_or("invalid portrait dimensions")?;
        avatar.draw_pixmap(
            0,
            0,
            self.avatar.as_ref(),
            &PixmapPaint {
                quality: FilterQuality::Bicubic,
                ..Default::default()
            },
            Transform::from_scale(
                size as f32 / self.avatar.width() as f32,
                size as f32 / self.avatar.height() as f32,
            ),
            None,
        );
        let center = width as f32 / 2.0;
        let avatar_y = height as f32 / 2.0 - 189.0 * scale;
        draw_centered_text(
            &mut background,
            &self.font,
            "akari",
            point(center, avatar_y + 325.0 * scale),
            35.0 * scale,
            4.0 * scale,
            foreground,
        );
        let text = "Getting your desktop ready";
        let text_width = get_text_width(&self.font, text, 12.0 * scale, scale);
        let status_left = center - (text_width + 27.0 * scale) / 2.0;
        draw_text(
            &mut background,
            &self.font,
            text,
            point(status_left, avatar_y + 355.0 * scale),
            12.0 * scale,
            scale,
            muted,
        );
        draw_centered_text(
            &mut background,
            &self.font,
            "HANKUI AKARI",
            point(center, height as f32 - 25.0 * scale),
            9.0 * scale,
            3.0 * scale,
            muted,
        );
        let pixels = background.clone();
        let dots_x = status_left + text_width + 11.5 * scale;
        let dots_y = avatar_y + 350.5 * scale;
        let avatar_x = (width as f32 - size as f32) / 2.0;
        let avatar_pad = (6.0 * scale).ceil() + 4.0;
        let dot_pad = (2.0 * scale).ceil() + 2.0;
        let dirty_rects = [
            clamp_rect(
                avatar_x - avatar_pad,
                avatar_y - 4.0 * scale - avatar_pad,
                avatar_x + size as f32 + avatar_pad,
                avatar_y + size as f32 + avatar_pad,
                width,
                height,
            ),
            clamp_rect(
                dots_x - dot_pad,
                dots_y - dot_pad,
                dots_x + 14.0 * scale + dot_pad,
                dots_y + dot_pad,
                width,
                height,
            ),
        ]
        .into_iter()
        .flatten()
        .collect();
        Ok(Scene {
            background,
            avatar,
            pixels,
            dirty_rects,
            scale,
            avatar_y,
            dots_x,
            dots_y,
        })
    }
}

impl Scene {
    pub fn draw(&mut self, seconds: f32) {
        let stride = self.pixels.width() as usize * 4;
        let bg_data = self.background.data();
        let px_data = self.pixels.data_mut();
        for rect in &self.dirty_rects {
            let x_bytes = rect.x as usize * 4;
            let len_bytes = rect.width as usize * 4;
            for row in rect.y as usize..(rect.y + rect.height) as usize {
                let start = row * stride + x_bytes;
                px_data[start..start + len_bytes]
                    .copy_from_slice(&bg_data[start..start + len_bytes]);
            }
        }
        let phase = seconds * std::f32::consts::TAU / 4.0;
        let x = (self.pixels.width() - self.avatar.width()) as f32 / 2.0;
        let y = self.avatar_y - (1.0 - phase.cos()) * 2.0 * self.scale;
        let rotation = -0.5 * phase.cos();
        self.pixels.draw_pixmap(
            0,
            0,
            self.avatar.as_ref(),
            &PixmapPaint {
                quality: FilterQuality::Bilinear,
                ..Default::default()
            },
            Transform::from_rotate_at(
                rotation,
                self.avatar.width() as f32 / 2.0,
                self.avatar.height() as f32 / 2.0,
            )
            .post_translate(x, y),
            None,
        );
        for index in 0..3 {
            let phase = ((seconds - index as f32 * 0.2) / 1.8).rem_euclid(1.0);
            let opacity = if phase < 0.6 {
                0.3 + 0.7 * (1.0 - ((phase - 0.3) / 0.3).abs())
            } else {
                0.3
            };
            let path = PathBuilder::from_circle(
                self.dots_x + index as f32 * 7.0 * self.scale,
                self.dots_y,
                1.5 * self.scale,
            )
            .unwrap();
            let mut paint = Paint::default();
            paint.set_color_rgba8(188, 162, 189, (opacity * 255.0) as u8);
            self.pixels.fill_path(
                &path,
                &paint,
                tiny_skia::FillRule::Winding,
                Transform::identity(),
                None,
            );
        }
    }

    pub fn has_size(&self, width: u32, height: u32) -> bool {
        self.pixels.width() == width && self.pixels.height() == height
    }

    pub fn save_png(&self, path: impl AsRef<Path>) -> Result {
        self.pixels.save_png(path)?;
        Ok(())
    }

    pub fn copy_xrgb(&self, target: &mut [u32]) {
        for (pixel, rgba) in target.iter_mut().zip(self.pixels.data().as_chunks::<4>().0) {
            *pixel = get_xrgb_pixel(rgba);
        }
    }

    pub fn get_dirty_rects(&self) -> &[DirtyRect] {
        &self.dirty_rects
    }

    pub fn copy_xrgb_strided(&self, target: &mut [u8], pitch: usize) {
        let row_bytes = self.pixels.width() as usize * 4;
        for (source, target_row) in self
            .pixels
            .data()
            .chunks_exact(row_bytes)
            .zip(target.chunks_mut(pitch))
        {
            for (rgba, pixel) in source
                .as_chunks::<4>()
                .0
                .iter()
                .zip(target_row.as_chunks_mut::<4>().0)
            {
                pixel.copy_from_slice(&get_xrgb_pixel(rgba).to_le_bytes());
            }
        }
    }

    pub fn copy_xrgb_dirty_strided(&self, target: &mut [u8], pitch: usize) {
        let src_stride = self.pixels.width() as usize * 4;
        let src_data = self.pixels.data();
        for rect in &self.dirty_rects {
            let x_bytes = rect.x as usize * 4;
            let len_bytes = rect.width as usize * 4;
            for row in rect.y as usize..(rect.y + rect.height) as usize {
                let src_start = row * src_stride + x_bytes;
                let dst_start = row * pitch + x_bytes;
                for (rgba, pixel) in src_data[src_start..src_start + len_bytes]
                    .as_chunks::<4>()
                    .0
                    .iter()
                    .zip(
                        target[dst_start..dst_start + len_bytes]
                            .as_chunks_mut::<4>()
                            .0,
                    )
                {
                    pixel.copy_from_slice(&get_xrgb_pixel(rgba).to_le_bytes());
                }
            }
        }
    }
}

fn clamp_rect(
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
    width: u32,
    height: u32,
) -> Option<DirtyRect> {
    let x0 = (min_x.floor().max(0.0) as u32).min(width);
    let y0 = (min_y.floor().max(0.0) as u32).min(height);
    let x1 = (max_x.ceil().max(0.0) as u32).min(width);
    let y1 = (max_y.ceil().max(0.0) as u32).min(height);
    (x1 > x0 && y1 > y0).then_some(DirtyRect {
        x: x0,
        y: y0,
        width: x1 - x0,
        height: y1 - y0,
    })
}

fn get_xrgb_pixel(rgba: &[u8; 4]) -> u32 {
    (u32::from(rgba[0]) << 16) | (u32::from(rgba[1]) << 8) | u32::from(rgba[2])
}

fn get_text_width(font: &FontVec, text: &str, size: f32, spacing: f32) -> f32 {
    let font = font.as_scaled(PxScale::from(size));
    text.chars()
        .map(|character| font.h_advance(font.glyph_id(character)) + spacing)
        .sum::<f32>()
        - spacing
}

fn draw_centered_text(
    pixels: &mut Pixmap,
    font: &FontVec,
    text: &str,
    center: ab_glyph::Point,
    size: f32,
    spacing: f32,
    color: [u8; 3],
) {
    let width = get_text_width(font, text, size, spacing);
    draw_text(
        pixels,
        font,
        text,
        point(center.x - width / 2.0, center.y),
        size,
        spacing,
        color,
    );
}

fn draw_text(
    pixels: &mut Pixmap,
    font: &FontVec,
    text: &str,
    position: ab_glyph::Point,
    size: f32,
    spacing: f32,
    color: [u8; 3],
) {
    let mut x = position.x;
    let scaled = font.as_scaled(PxScale::from(size));
    let width = pixels.width() as i32;
    let height = pixels.height() as i32;
    for character in text.chars() {
        let id = font.glyph_id(character);
        let glyph = id.with_scale_and_position(size, point(x, position.y));
        if let Some(outlined) = font.outline_glyph(glyph) {
            let bounds = outlined.px_bounds();
            outlined.draw(|x, y, coverage| {
                let x = bounds.min.x as i32 + x as i32;
                let y = bounds.min.y as i32 + y as i32;
                if x < 0 || y < 0 || x >= width || y >= height {
                    return;
                }
                let offset = ((y * width + x) * 4) as usize;
                for (channel, value) in color.iter().enumerate() {
                    let target = &mut pixels.data_mut()[offset + channel];
                    *target = (*target as f32 * (1.0 - coverage) + *value as f32 * coverage).round()
                        as u8;
                }
            });
        }
        x += scaled.h_advance(id) + spacing;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_outputs_share_opaque_pixels_at_wide_tall_and_small_sizes() {
        let renderer = Renderer::load().unwrap();
        for (width, height) in [(1280, 720), (720, 1280), (320, 200)] {
            let mut scene = renderer.create_scene(width, height, false).unwrap();
            assert!(scene.has_size(width, height));
            scene.draw(0.0);
            let first = scene.pixels.data().to_vec();
            let mut xrgb = vec![0; (width * height) as usize];
            scene.copy_xrgb(&mut xrgb);
            assert_eq!(xrgb[0], 0xfaf7f2);
            assert!(first.as_chunks::<4>().0.iter().all(|pixel| pixel[3] == 255));
            assert!(xrgb.iter().any(|pixel| *pixel != 0xfaf7f2));

            let pitch = width as usize * 4 + 16;
            let mut strided = vec![0xff; pitch * height as usize];
            scene.copy_xrgb_strided(&mut strided, pitch);
            assert_eq!(
                u32::from_le_bytes(strided[..4].try_into().unwrap()),
                xrgb[0]
            );
            assert!(
                strided[width as usize * 4..pitch]
                    .iter()
                    .all(|&b| b == 0xff)
            );

            scene.draw(1.0);
            assert_ne!(scene.pixels.data(), first);
        }
    }
}
