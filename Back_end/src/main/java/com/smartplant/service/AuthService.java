package com.smartplant.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.smartplant.config.SmartPlantProperties;
import com.smartplant.domain.entity.SysUser;
import com.smartplant.dto.LoginRequest;
import com.smartplant.dto.LoginResponse;
import com.smartplant.mapper.SysUserMapper;
import com.smartplant.security.JwtTokenProvider;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final AuthenticationManager authenticationManager;
    private final JwtTokenProvider jwtTokenProvider;
    private final SysUserMapper sysUserMapper;
    private final SmartPlantProperties properties;

    public LoginResponse login(LoginRequest request) {
        Authentication authentication = authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(request.getUsername(), request.getPassword()));
        String username = authentication.getName();
        String token = jwtTokenProvider.createToken(username);
        SysUser user = sysUserMapper.selectOne(new LambdaQueryWrapper<SysUser>()
                .eq(SysUser::getUsername, username)
                .last("LIMIT 1"));
        String displayName = user != null && user.getDisplayName() != null ? user.getDisplayName() : username;
        return new LoginResponse(token, "Bearer", properties.getJwt().getExpireHours(), username, displayName);
    }
}
