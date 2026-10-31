package com.smartplant.security;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.smartplant.domain.entity.SysUser;
import com.smartplant.mapper.SysUserMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class CustomUserDetailsService implements UserDetailsService {

    private final SysUserMapper sysUserMapper;

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        SysUser user = sysUserMapper.selectOne(new LambdaQueryWrapper<SysUser>()
                .eq(SysUser::getUsername, username)
                .last("LIMIT 1"));
        if (user == null) {
            throw new UsernameNotFoundException("用户不存在");
        }
        return User.builder()
                .username(user.getUsername())
                .password(user.getPasswordHash())
                .disabled(Boolean.FALSE.equals(user.getEnabled()))
                .roles("USER")
                .build();
    }
}
