// HydroWin — корпус с кабельными каналами (вычитание объёмов)
// Плата: LilyGO T-A7670G + L76K  110×34×18 мм
// DC-DC: 63×27×10 мм (до 66 мм с разъёмами)
//
// STL: hydrowin_shell.stl | standoffs_* | hydrowin_lid.stl | hydrowin_base.stl
// Пересборка: .\export-stl.ps1

/* [Габариты корпуса, мм] */
inner_length = 150;   // монтажная зона с запасом под плату 110 мм
inner_width  = 72;
inner_height = 42;
wall         = 2.8;
floor        = 2.8;
lid_thickness = 3.2;
lip_depth     = 2.0;
lip_clearance = 0.35;

/* [Плата LilyGO T-A7670G + L76K] */
board_len = 110;
board_w   = 34;
board_h   = 18;
board_x0  = (inner_length - board_len) / 2;

board_standoff_h = 10;
board_standoff_d = 6.5;
board_hole_d     = 3.2;
board_hole_inset = 4;

/* [DC-DC 24→5V] */
dcdc_len = 66;
dcdc_w   = 27;
dcdc_h   = 10;
dcdc_x0  = (inner_length - dcdc_len) / 2;
dcdc_y0  = 4;

dcdc_standoff_h = 4;
dcdc_standoff_d = 6.5;
dcdc_hole_d     = 3.2;
dcdc_hole_inset = 4;

board_y0 = dcdc_y0 + dcdc_w + 6;

/* [BNC ×6 — задняя стенка +Y] */
bnc_hole_d  = 14.0;
bnc_count   = 6;
bnc_pitch   = 17.5;
bnc_start_x = (inner_length - (bnc_count - 1) * bnc_pitch) / 2;
bnc_z       = 12;

/* [SMA LTE + GPS] */
sma_hole_d = 6.6;
sma1_x = board_x0 + 8;
sma2_x = board_x0 + board_len - 8;
sma_z  = 32;

/* [PG7 — левая стенка, ось = плоскость кабельных канавок] */
pg7_hole_d = 12.8;
pg7_landing_r = 10;
pg7_y = dcdc_y0 + dcdc_w / 2;
// pg7_z задаётся в cable_routing.scad (= cable_plane_z)

usb_slot_w = 10;
usb_slot_h = 4;
usb_y = board_y0 + board_w / 2;
usb_z = board_standoff_h + 6;

/* [Вентиляция DC-DC — жалюзи в полу] */
louver_fin_t  = 1.5;
louver_gap    = 2.0;
louver_angle  = 45;
louver_margin = 3;
louver_fillet = 1.0;

/* [Крышка] */
lid_screw_d = 3.4;
lid_screw_inset = 8;
screw_pilot_d = 2.3;
screw_pilot_depth = 8;

/* [Уплотнитель] */
gasket_groove_w = 2.8;
gasket_groove_d = 2.0;

$fn = 48;

outer_l = inner_length + 2 * wall;
outer_w = inner_width + 2 * wall;
outer_h = inner_height + floor;

function bnc_x(i) = bnc_start_x + i * bnc_pitch;

function board_mount_points() = [
    [board_x0 + board_hole_inset, board_y0 + board_hole_inset],
    [board_x0 + board_len - board_hole_inset, board_y0 + board_hole_inset],
    [board_x0 + board_hole_inset, board_y0 + board_w - board_hole_inset],
    [board_x0 + board_len - board_hole_inset, board_y0 + board_w - board_hole_inset]
];

function dcdc_mount_points() = [
    [dcdc_x0 + dcdc_hole_inset, dcdc_y0 + dcdc_hole_inset],
    [dcdc_x0 + dcdc_len - dcdc_hole_inset, dcdc_y0 + dcdc_hole_inset],
    [dcdc_x0 + dcdc_hole_inset, dcdc_y0 + dcdc_w - dcdc_hole_inset],
    [dcdc_x0 + dcdc_len - dcdc_hole_inset, dcdc_y0 + dcdc_w - dcdc_hole_inset]
];

include <cable_routing.scad>

module standoff(x, y, h, od, hole_d) {
    translate([wall + x, wall + y, floor])
        difference() {
            cylinder(h = h, d = od);
            translate([0, 0, -0.1])
                cylinder(h = h + 0.2, d = hole_d);
        }
}

// Жалюзи 45° в полу над зоной DC-DC: вычитаем световые зазоры, ламели остаются
module dcdc_louver_grille() {
    ox = dcdc_x0 + louver_margin;
    oy = dcdc_y0 + louver_margin;
    lx = dcdc_len - 2 * louver_margin;
    ly = dcdc_w - 2 * louver_margin;
    pitch = louver_fin_t + louver_gap;
    count = floor(lx / pitch);
    cy = oy + ly / 2;

    intersection() {
        translate([wall + ox, wall + oy, -0.1])
            cube([lx, ly, floor + 0.2]);

        for (i = [0 : count - 1]) {
            gx = ox + louver_fin_t + i * pitch;
            translate([wall + gx, wall + cy, -0.1])
                rotate([0, louver_angle, 0])
                    cube([louver_gap, ly + 8, floor + 10], center = true);
        }
    }
}

module lid_screw_holes_base() {
    for (xy = [[lid_screw_inset, lid_screw_inset],
               [outer_l - lid_screw_inset, lid_screw_inset],
               [lid_screw_inset, outer_w - lid_screw_inset],
               [outer_l - lid_screw_inset, outer_w - lid_screw_inset]]) {
        translate([xy[0], xy[1], outer_h - screw_pilot_depth])
            cylinder(h = screw_pilot_depth + 0.1, d = screw_pilot_d);
    }
}

module gasket_groove_cut() {
    inset = wall + gasket_groove_w / 2;
    translate([0, 0, outer_h - gasket_groove_d])
        union() {
            translate([inset, inset, 0])
                cube([outer_l - 2 * inset, gasket_groove_w, gasket_groove_d + 0.1]);
            translate([inset, outer_w - inset - gasket_groove_w, 0])
                cube([outer_l - 2 * inset, gasket_groove_w, gasket_groove_d + 0.1]);
            translate([inset, inset, 0])
                cube([gasket_groove_w, outer_w - 2 * inset, gasket_groove_d + 0.1]);
            translate([outer_l - inset - gasket_groove_w, inset, 0])
                cube([gasket_groove_w, outer_w - 2 * inset, gasket_groove_d + 0.1]);
        }
}

module bnc_holes() {
    for (i = [0 : bnc_count - 1]) {
        translate([wall + bnc_x(i), wall + inner_width + 0.1, floor + bnc_z])
            rotate([-90, 0, 0])
                cylinder(h = wall + 0.2, d = bnc_hole_d);
    }
}

// PG7: сквозное Ø12.8 мм, ось Z = cable_plane_z
module pg7_hole_cut() {
    translate([-0.1, wall + pg7_y, floor + cable_plane_z])
        rotate([0, 90, 0])
            cylinder(h = wall + 0.2, d = pg7_hole_d);
}

module shell_body() {
    difference() {
        cube([outer_l, outer_w, outer_h]);

        translate([wall, wall, floor])
            cube([inner_length, inner_width, inner_height + 0.1]);

        all_cable_routes_safe();
        dcdc_louver_grille();
        gasket_groove_cut();
        lid_screw_holes_base();
        bnc_holes();

        translate([wall + sma1_x, wall + inner_width + 0.1, floor + sma_z])
            rotate([-90, 0, 0]) cylinder(h = wall + 0.2, d = sma_hole_d);
        translate([wall + sma2_x, wall + inner_width + 0.1, floor + sma_z])
            rotate([-90, 0, 0]) cylinder(h = wall + 0.2, d = sma_hole_d);

        pg7_hole_cut();

        translate([-0.1, wall + usb_y - usb_slot_w / 2, floor + usb_z])
            rotate([0, 90, 0]) cube([wall + 0.2, usb_slot_w, usb_slot_h]);
    }
}

module board_standoffs() {
    for (p = board_mount_points())
        standoff(p[0], p[1], board_standoff_h, board_standoff_d, board_hole_d);
}

module dcdc_standoffs() {
    for (p = dcdc_mount_points())
        standoff(p[0], p[1], dcdc_standoff_h, dcdc_standoff_d, dcdc_hole_d);
}

module base_body() {
    shell_body();
    board_standoffs();
    dcdc_standoffs();
}

module lid_body() {
    lip_l = inner_length + 2 * lip_clearance;
    lip_w = inner_width + 2 * lip_clearance;

    difference() {
        union() {
            cube([outer_l, outer_w, lid_thickness]);
            translate([wall - lip_clearance, wall - lip_clearance, -lip_depth])
                cube([lip_l, lip_w, lip_depth]);
        }
        translate([lid_screw_inset, lid_screw_inset, -0.1])
            cylinder(h = lid_thickness + lip_depth + 0.2, d = lid_screw_d);
        translate([outer_l - lid_screw_inset, lid_screw_inset, -0.1])
            cylinder(h = lid_thickness + lip_depth + 0.2, d = lid_screw_d);
        translate([lid_screw_inset, outer_w - lid_screw_inset, -0.1])
            cylinder(h = lid_thickness + lip_depth + 0.2, d = lid_screw_d);
        translate([outer_l - lid_screw_inset, outer_w - lid_screw_inset, -0.1])
            cylinder(h = lid_thickness + lip_depth + 0.2, d = lid_screw_d);
    }
}

// %translate([wall + board_x0, wall + board_y0, floor + board_standoff_h])
//     cube([board_len, board_w, board_h]);
// %translate([wall + dcdc_x0, wall + dcdc_y0, floor + dcdc_standoff_h])
//     cube([dcdc_len, dcdc_w, dcdc_h]);
