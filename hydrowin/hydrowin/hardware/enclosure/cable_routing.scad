// Кабельные каналы и посадочные места (вычитание из оболочки)
// Подключается из hydrowin_enclosure.scad

// ── Сечения канавок ──
power_w = 2.6;
power_d = 3.0;
v5_w    = 2.3;
v5_d    = 2.5;
sig_w   = 1.5;
sig_d   = 1.8;
sig_pitch = 3.0;
bnc_gw  = 3.0;
bnc_gd  = 3.2;

fillet_r   = 4.0;
keepout_m  = 1.5;

// Плоскость оси проводов питания (совпадает с осью PG7 по Z)
cable_plane_z = power_d - 2.5 / 2;

// Предохранитель
fuse_pocket_l = 42;
fuse_pocket_w = 14;
fuse_pocket_h = 26;

// Резистор 0.25–0.5 W
res_pocket_l = 8.0;
res_pocket_w = 3.0;
res_pocket_d = 3.0;

// ── Вспомогательные функции ──
function v2(x, y) = [x, y];
function v3(x, y, z) = [x, y, z];

function seg_len(a, b) = norm([b[0] - a[0], b[1] - a[1]]);

// Прямоугольный сегмент канавки в дне полости (внутренние координаты)
module groove_rect_seg(x, y, lx, ly, w, d) {
    gw = (lx > 0.01) ? lx : w;
    gh = (ly > 0.01) ? ly : w;
    gx = (lx > 0.01) ? x : x - w / 2;
    gy = (ly > 0.01) ? y : y - w / 2;
    translate([wall + gx, wall + gy, floor - d])
        cube([gw, gh, d + 0.08]);
}

// Сегмент между двумя точками с прямоугольным сечением
module groove_line(p0, p1, w, d) {
    dx = p1[0] - p0[0];
    dy = p1[1] - p0[1];
    len = sqrt(dx * dx + dy * dy);
    if (len > 0.05) {
        ang = atan2(dy, dx);
        translate([wall + p0[0], wall + p0[1], floor - d])
            rotate([0, 0, ang])
                translate([0, -w / 2, 0])
                    cube([len, w, d + 0.08]);
    }
}

// Скругление поворота R >= fillet_r (четверть цилиндра в дне)
module groove_corner(cx, cy, w, d, r = fillet_r) {
    translate([wall + cx, wall + cy, floor - d])
        cylinder(h = d + 0.08, r = r + w / 2, $fn = 40);
}

// Плавный переход канавка → карман (слияние призм)
module groove_to_pocket(px, py, pl, pw, pd, gw, gd) {
    union() {
        groove_rect_seg(px, py, pl, pw, gw, gd);
        hull() {
            translate([wall + px, wall + py, floor - gd])
                cube([pl, pw, 0.01]);
            translate([wall + px - 1, wall + py - 1, floor - pd])
                cube([pl + 2, pw + 2, 0.01]);
        }
    }
}

// Карман в полости (резистор / предохранитель)
module pocket_box(x, y, l, w, h) {
    translate([wall + x, wall + y, floor])
        cube([l, w, h + 0.08]);
}

// Зоны, где канавки запрещены (крепёж, BNC)
module routing_keepout_zone(x, y, od) {
    translate([wall + x, wall + y, floor - 0.2])
        cylinder(h = inner_height + 1, d = od + 2 * keepout_m, $fn = 36);
}

module all_routing_keepouts() {
  for (p = board_mount_points())
        routing_keepout_zone(p[0], p[1], board_standoff_d);
  for (p = dcdc_mount_points())
        routing_keepout_zone(p[0], p[1], dcdc_standoff_d);
  for (i = [0 : bnc_count - 1])
        routing_keepout_zone(bnc_x(i), inner_width - 2, bnc_hole_d);
}

// Канавки минус зоны keepout (обход крепежа и BNC)
module routed_grooves() {
    difference() {
        children();
        all_routing_keepouts();
    }
}

// Полилиния с угловыми скруглениями
module groove_path(pts, w, d, cr = fillet_r) {
    for (i = [0 : len(pts) - 2])
        groove_line(pts[i], pts[i + 1], w, d);

    if (len(pts) > 2)
        for (i = [1 : len(pts) - 2])
            groove_corner(pts[i][0], pts[i][1], w, d, cr);
}

// ── Трассы ──

// PG7 → предохранитель → вход DC-DC (старт у отверстия PG7)
module power_input_route() {
    fuse_x = 6;
    fuse_y = pg7_y - fuse_pocket_l / 2;
    dcdc_in = v2(dcdc_x0 + 18, dcdc_y0 + dcdc_w + 3);

    routed_grooves()
    union() {
        groove_path(
            [v2(pg7_landing_r + 1, pg7_y),
             v2(fuse_x + fuse_pocket_w + 2, pg7_y),
             v2(fuse_x + fuse_pocket_w + 2, fuse_y + fuse_pocket_l / 2),
             dcdc_in],
            power_w, power_d
        );
        pocket_box(fuse_x, fuse_y, fuse_pocket_w, fuse_pocket_l, fuse_pocket_h);
    }
}

// 5V: выход DC-DC → VIN ESP32
module power_5v_route() {
    p0 = v2(dcdc_x0 + dcdc_len - 16, dcdc_y0 + 4);
    p1 = v2(dcdc_x0 + dcdc_len - 16, board_y0 - 3);
    p2 = v2(board_x0 + 12, board_y0 - 3);
    p3 = v2(board_x0 + 12, board_y0 + 6);

    routed_grooves()
        groove_path([p0, p1, p2, p3], v5_w, v5_d);
}

// 6 сигнальных линий + карманы резисторов у платы
module signal_routes() {
    bus_y = board_y0 + board_w + 5;
    x0 = board_x0 + board_len / 2 - (bnc_count - 1) * sig_pitch / 2;

    routed_grooves()
    union() {
        for (i = [0 : bnc_count - 1]) {
            sx = x0 + i * sig_pitch;
            groove_path(
                [v2(sx, board_y0 + board_w - 2), v2(sx, bus_y),
                 v2(bnc_x(i), bus_y), v2(bnc_x(i), inner_width - 10)],
                sig_w, sig_d
            );
            rx = sx - res_pocket_w / 2;
            ry = board_y0 + board_w - 1;
            groove_to_pocket(rx, ry, res_pocket_l, res_pocket_w, res_pocket_d, sig_w, sig_d);
        }
    }
}

// BNC: усиленные канавки от шины к разъёмам
module bnc_output_routes() {
    bus_y = board_y0 + board_w + 8;

    routed_grooves()
        for (i = [0 : bnc_count - 1])
            groove_path(
                [v2(bnc_x(i), bus_y), v2(bnc_x(i), inner_width - 8)],
                bnc_gw, bnc_gd
            );
}

module all_cable_routes() {
    power_input_route();
    power_5v_route();
    signal_routes();
    bnc_output_routes();
}

// Защита площадки PG7: канавки не режут зону R10 на внутренней стенке
module pg7_landing_keepout() {
    translate([wall - 0.05, wall + pg7_y, floor + cable_plane_z - pg7_landing_r])
        cube([0.15, 2 * pg7_landing_r, 2 * pg7_landing_r]);
}

module all_cable_routes_safe() {
    difference() {
        all_cable_routes();
        pg7_landing_keepout();
    }
}
