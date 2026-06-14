/**************************************************************************/
/*  ik_kabsch_6d.cpp                                                      */
/**************************************************************************/

#include "ik_kabsch_6d.h"

#include "core/math/math_funcs.h"

void IKKabsch6D::set_cross(double r_u[3][3], int p_j, int p_j1, int p_j2) {
	const double x = r_u[1][p_j1] * r_u[2][p_j2] - r_u[2][p_j1] * r_u[1][p_j2];
	const double y = r_u[2][p_j1] * r_u[0][p_j2] - r_u[0][p_j1] * r_u[2][p_j2];
	const double z = r_u[0][p_j1] * r_u[1][p_j2] - r_u[1][p_j1] * r_u[0][p_j2];
	const double n = Math::sqrt(x * x + y * y + z * z) + 1e-300;
	r_u[0][p_j] = x / n;
	r_u[1][p_j] = y / n;
	r_u[2][p_j] = z / n;
}

void IKKabsch6D::svd3(const double p_m[3][3], double r_u[3][3], double r_v[3][3], double r_sigma[3]) {
	double a[3][3];
	double v[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			a[i][j] = p_m[i][j];
		}
	}
	for (int sweep = 0; sweep < 40; sweep++) {
		bool converged = true;
		for (int p = 0; p < 3; p++) {
			for (int q = p + 1; q < 3; q++) {
				const double alpha = a[0][p] * a[0][p] + a[1][p] * a[1][p] + a[2][p] * a[2][p];
				const double beta = a[0][q] * a[0][q] + a[1][q] * a[1][q] + a[2][q] * a[2][q];
				const double gamma = a[0][p] * a[0][q] + a[1][p] * a[1][q] + a[2][p] * a[2][q];
				if (Math::abs(gamma) > 1e-17 * Math::sqrt(alpha * beta + 1e-300)) {
					converged = false;
					const double zeta = (beta - alpha) / (2.0 * gamma);
					const double t = (zeta >= 0.0 ? 1.0 : -1.0) / (Math::abs(zeta) + Math::sqrt(1.0 + zeta * zeta));
					const double c = 1.0 / Math::sqrt(1.0 + t * t);
					const double s = c * t;
					for (int k = 0; k < 3; k++) {
						const double ap = a[k][p];
						const double aq = a[k][q];
						a[k][p] = c * ap - s * aq;
						a[k][q] = s * ap + c * aq;
						const double vp = v[k][p];
						const double vq = v[k][q];
						v[k][p] = c * vp - s * vq;
						v[k][q] = s * vp + c * vq;
					}
				}
			}
		}
		if (converged) {
			break;
		}
	}
	double sig[3];
	for (int j = 0; j < 3; j++) {
		sig[j] = Math::sqrt(a[0][j] * a[0][j] + a[1][j] * a[1][j] + a[2][j] * a[2][j]);
	}
	int order[3] = { 0, 1, 2 };
	for (int i = 0; i < 3; i++) {
		for (int j = i + 1; j < 3; j++) {
			if (sig[order[j]] > sig[order[i]]) {
				const int tmp = order[i];
				order[i] = order[j];
				order[j] = tmp;
			}
		}
	}
	const double eps = 1e-12 * (sig[order[0]] + 1e-300);
	for (int j = 0; j < 3; j++) {
		const int o = order[j];
		r_sigma[j] = sig[o];
		for (int k = 0; k < 3; k++) {
			r_v[k][j] = v[k][o];
			r_u[k][j] = (sig[o] > eps) ? (a[k][o] / sig[o]) : 0.0;
		}
	}
	// Complete rank-deficient U columns into a right-handed orthonormal frame. sigma is
	// descending, so deficiency runs from the last column. Rank 1 (a single correspondence)
	// leaves the swing axis free -> any perpendicular completion is a valid rotation.
	if (r_sigma[0] <= eps) {
		for (int i = 0; i < 3; i++) {
			for (int j = 0; j < 3; j++) {
				r_u[i][j] = (i == j) ? 1.0 : 0.0;
			}
		}
	} else if (r_sigma[1] <= eps) {
		const Vector3 c0(r_u[0][0], r_u[1][0], r_u[2][0]);
		const Vector3 c1 = c0.get_any_perpendicular().normalized();
		const Vector3 c2 = c0.cross(c1).normalized();
		r_u[0][1] = c1.x;
		r_u[1][1] = c1.y;
		r_u[2][1] = c1.z;
		r_u[0][2] = c2.x;
		r_u[1][2] = c2.y;
		r_u[2][2] = c2.z;
	} else if (r_sigma[2] <= eps) {
		set_cross(r_u, 2, 0, 1);
	}
}

Basis IKKabsch6D::kabsch(const Vector3 *p_rest, const Vector3 *p_tgt, int p_count) {
	// Cross-covariance M = sum tgt_i * rest_i^T (m[row=tgt][col=rest]).
	double m[3][3] = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } };
	for (int i = 0; i < p_count; i++) {
		const Vector3 &r = p_rest[i];
		const Vector3 &t = p_tgt[i];
		m[0][0] += t.x * r.x;
		m[0][1] += t.x * r.y;
		m[0][2] += t.x * r.z;
		m[1][0] += t.y * r.x;
		m[1][1] += t.y * r.y;
		m[1][2] += t.y * r.z;
		m[2][0] += t.z * r.x;
		m[2][1] += t.z * r.y;
		m[2][2] += t.z * r.z;
	}
	double u[3][3];
	double v[3][3];
	double sigma[3];
	svd3(m, u, v, sigma);
	// det(U V^T); flip the smallest singular direction if it is a reflection.
	double uvt[3][3];
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			uvt[i][j] = u[i][0] * v[j][0] + u[i][1] * v[j][1] + u[i][2] * v[j][2];
		}
	}
	const double det = uvt[0][0] * (uvt[1][1] * uvt[2][2] - uvt[1][2] * uvt[2][1]) - uvt[0][1] * (uvt[1][0] * uvt[2][2] - uvt[1][2] * uvt[2][0]) + uvt[0][2] * (uvt[1][0] * uvt[2][1] - uvt[1][1] * uvt[2][0]);
	const double d = (det >= 0.0) ? 1.0 : -1.0;
	// R = U * diag(1,1,d) * V^T; columns ax/ay/az.
	const Vector3 ax(u[0][0] * v[0][0] + u[0][1] * v[0][1] + d * u[0][2] * v[0][2],
			u[1][0] * v[0][0] + u[1][1] * v[0][1] + d * u[1][2] * v[0][2],
			u[2][0] * v[0][0] + u[2][1] * v[0][1] + d * u[2][2] * v[0][2]);
	const Vector3 ay(u[0][0] * v[1][0] + u[0][1] * v[1][1] + d * u[0][2] * v[1][2],
			u[1][0] * v[1][0] + u[1][1] * v[1][1] + d * u[1][2] * v[1][2],
			u[2][0] * v[1][0] + u[2][1] * v[1][1] + d * u[2][2] * v[1][2]);
	const Vector3 az(u[0][0] * v[2][0] + u[0][1] * v[2][1] + d * u[0][2] * v[2][2],
			u[1][0] * v[2][0] + u[1][1] * v[2][1] + d * u[1][2] * v[2][2],
			u[2][0] * v[2][0] + u[2][1] * v[2][1] + d * u[2][2] * v[2][2]);
	return Basis(ax, ay, az);
}
